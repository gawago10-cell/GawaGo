import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  tearDown(GawaGoApi.resetClient);

  test('authenticated requests include the bearer token', () async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'test-token', role: 'worker'),
    );
    String? authorization;
    GawaGoApi.setClient(
      MockClient((request) async {
        authorization = request.headers['authorization'];
        return http.Response('{"ok":true}', 200);
      }),
    );

    await GawaGoApi.get('/accounts/me/');

    expect(authorization, 'Bearer test-token');
  });

  test('401 expires and clears the current session', () async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'expired-token', role: 'worker'),
    );
    final expirationEvent = SessionStorage.sessionExpired.value;
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response('{"detail":"Token expired."}', 401),
      ),
    );

    await expectLater(
      GawaGoApi.get('/accounts/me/'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.type, 'type', ApiErrorType.unauthorized)
            .having((error) => error.statusCode, 'status', 401),
      ),
    );

    expect(SessionStorage.currentSession, isNull);
    expect(SessionStorage.sessionExpired.value, expirationEvent + 1);
  });

  test('403 preserves the session and reports a forbidden error', () async {
    const session = AuthSession(accessToken: 'valid-token', role: 'household');
    await SessionStorage.save(session);
    GawaGoApi.setClient(
      MockClient(
        (_) async =>
            http.Response('{"detail":"Verification is required."}', 403),
      ),
    );

    await expectLater(
      GawaGoApi.post('/jobs/', body: const {}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.type, 'type', ApiErrorType.forbidden)
            .having(
              (error) => error.message,
              'message',
              'Verification is required.',
            ),
      ),
    );

    expect(SessionStorage.currentSession, same(session));
  });

  test('429 is classified as rate limited with the wait spelled out', () async {
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response(
          '{"detail":"Request was throttled. Expected available in 42 seconds."}',
          429,
        ),
      ),
    );

    await expectLater(
      GawaGoApi.post('/accounts/login/', body: const {}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.type, 'type', ApiErrorType.rateLimited)
            .having(
              (error) => error.message,
              'message',
              'Too many attempts. Please wait 42 seconds and try again.',
            ),
      ),
    );
  });

  test('a throttle response without a wait time still reads plainly', () async {
    GawaGoApi.setClient(
      MockClient((_) async => http.Response('{"detail":"Throttled."}', 429)),
    );

    await expectLater(
      GawaGoApi.post('/accounts/login/', body: const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Too many attempts. Please wait a moment and try again.',
        ),
      ),
    );
  });

  test('field validation errors are converted to readable messages', () async {
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'service_rate': ['This field is required.'],
            'schedule': ['Enter a valid date.'],
          }),
          400,
        ),
      ),
    );

    await expectLater(
      GawaGoApi.post('/jobs/', body: const {}, authenticated: false),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Service rate: This field is required.'),
        ),
      ),
    );
  });

  test('client failures are classified as network errors', () async {
    GawaGoApi.setClient(
      MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      GawaGoApi.get('/jobs/', authenticated: false),
      throwsA(
        isA<ApiException>().having(
          (error) => error.isNetworkError,
          'network error',
          isTrue,
        ),
      ),
    );
  });

  test('list endpoints accept DRF paginated results', () async {
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'count': 1,
            'next': null,
            'previous': null,
            'results': [
              {'id': 7, 'title': 'Cleaning'},
            ],
          }),
          200,
        ),
      ),
    );

    final data = await GawaGoApi.getList('/jobs/');

    expect(data, hasLength(1));
    expect(data.first['title'], 'Cleaning');
  });

  test('list endpoints follow next links across every page', () async {
    final requested = <String>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        requested.add(request.url.toString());
        final page = request.url.queryParameters['page'];
        final body = switch (page) {
          null => {
            'count': 3,
            'next': 'http://testserver/api/reviews/?page=2',
            'previous': null,
            'results': [
              {'id': 1},
            ],
          },
          '2' => {
            'count': 3,
            'next': 'http://testserver/api/reviews/?page=3',
            'previous': 'http://testserver/api/reviews/',
            'results': [
              {'id': 2},
            ],
          },
          _ => {
            'count': 3,
            'next': null,
            'previous': 'http://testserver/api/reviews/?page=2',
            'results': [
              {'id': 3},
            ],
          },
        };
        return http.Response(jsonEncode(body), 200);
      }),
    );

    final data = await GawaGoApi.getList('/reviews/');

    expect(data.map((item) => item['id']), [1, 2, 3]);
    expect(requested, hasLength(3));
    expect(requested.last, 'http://testserver/api/reviews/?page=3');
  });

  test('list endpoints still accept plain arrays', () async {
    GawaGoApi.setClient(
      MockClient((_) async => http.Response('[{"id":2}]', 200)),
    );

    final data = await GawaGoApi.getList('/notifications/');

    expect(data, hasLength(1));
    expect(data.first['id'], 2);
  });

  test('multipart post sends every selected job image', () async {
    final directory = await Directory.systemTemp.createTemp('gawago-images');
    final first = File('${directory.path}/first.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final second = File('${directory.path}/second.png')
      ..writeAsBytesSync([4, 5, 6]);
    String body = '';
    String contentType = '';
    GawaGoApi.setClient(
      MockClient((request) async {
        body = request.body;
        contentType = request.headers['content-type'] ?? '';
        return http.Response('{"id":1}', 201);
      }),
    );

    await GawaGoApi.multipartPostMany(
      '/jobs/',
      fields: const {'title': 'Cleaning'},
      fileField: 'images',
      filePaths: [first.path, second.path],
    );

    expect(contentType, startsWith('multipart/form-data'));
    expect(RegExp('name="images"').allMatches(body), hasLength(2));
    expect(body, contains('first.jpg'));
    expect(body, contains('second.png'));
    await directory.delete(recursive: true);
  });

  group('why a session ended', () {
    Future<void> signedInThenRejectedWith(String detail) async {
      await SessionStorage.save(
        const AuthSession(accessToken: 'live-token', role: 'worker'),
      );
      GawaGoApi.setClient(
        MockClient((_) async => http.Response('{"detail":"$detail"}', 401)),
      );
      await expectLater(
        GawaGoApi.get('/accounts/me/'),
        throwsA(isA<ApiException>()),
      );
    }

    test('a suspension keeps the server reason for the person to read', () async {
      await signedInThenRejectedWith(
        'This account is suspended until 2026-10-20 09:00. Contact support for assistance.',
      );

      expect(SessionStorage.endedMessage, contains('suspended until'));
    });

    test('a block keeps the server reason too', () async {
      await signedInThenRejectedWith(
        'This account has been blocked. Contact support for assistance.',
      );

      expect(SessionStorage.endedMessage, contains('blocked'));
    });

    test('an ordinary expired token does not quote the server', () async {
      await signedInThenRejectedWith('Token expired.');

      expect(SessionStorage.endedMessage, isNull);
    });

    test(
      'the endpoint that rejects a 401 with a map body works for lists too',
      () async {
        await SessionStorage.save(
          const AuthSession(accessToken: 'live-token', role: 'worker'),
        );
        GawaGoApi.setClient(
          MockClient(
            (_) async => http.Response(
              '{"detail":"This account has been blocked."}',
              401,
            ),
          ),
        );

        await expectLater(
          GawaGoApi.getList('/notifications/'),
          throwsA(isA<ApiException>()),
        );
        expect(SessionStorage.endedMessage, contains('blocked'));
      },
    );
  });
}
