import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/features/chat/data/chat_models.dart';
import 'package:gawago_mobile/src/features/chat/presentation/chat_screen.dart';
import 'package:gawago_mobile/src/features/chat/presentation/conversations_view.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _conversation = ChatConversation(
  id: 7,
  jobTitle: 'Deep clean',
  statusLabel: 'In progress',
  otherPartyName: 'Hana Tester',
  otherPartyRole: 'household',
  otherPartyPhotoUrl: '',
  unreadCount: 0,
);

Map<String, dynamic> _message(int id, String content, {bool mine = false}) => {
  'id': id,
  'conversation_id': 7,
  'sender_id': mine ? 2 : 1,
  'sender_name': mine ? 'Wes Tester' : 'Hana Tester',
  'is_mine': mine,
  'content': content,
  'created_at': '2026-09-23T08:00:00Z',
  'is_read': mine,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Pushes the chat screen on top of a blank page so the test can pop it.
Future<void> _openChat(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ChatScreen(
                conversation: _conversation,
                pollInterval: Duration(seconds: 4),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _closeChat(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
  });

  tearDown(GawaGoApi.resetClient);

  testWidgets('conversations list shows the empty state with no hires', (
    tester,
  ) async {
    GawaGoApi.setClient(MockClient((request) async => _json([])));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConversationsView(role: 'worker')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Chat becomes available once you get hired.'),
      findsOneWidget,
    );
  });

  testWidgets('conversations list shows name, last message and unread badge', (
    tester,
  ) async {
    GawaGoApi.setClient(
      MockClient(
        (request) async => _json([
          {
            'id': 7,
            'job_title': 'Deep clean',
            'status_label': 'In progress',
            'other_party': {
              'name': 'Hana Tester',
              'role': 'household',
              'photo_url': '',
            },
            'last_message': _message(3, 'hello'),
            'unread_count': 2,
          },
        ]),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConversationsView(role: 'worker')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hana Tester'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('chat loads history, sends optimistically and polls with after', (
    tester,
  ) async {
    final requests = <String>[];
    final server = [_message(1, 'hello')];
    GawaGoApi.setClient(
      MockClient((request) async {
        requests.add(
          '${request.method} ${request.url.path}?${request.url.query}',
        );
        if (request.url.path.endsWith('/read/')) {
          return _json({'marked_read': 1});
        }
        if (request.method == 'POST') {
          final content = jsonDecode(request.body)['content'] as String;
          final saved = _message(server.length + 1, content, mine: true);
          server.add(saved);
          return _json(saved, 201);
        }
        final after = int.tryParse(request.url.queryParameters['after'] ?? '');
        return _json(
          server
              .where((m) => after == null || (m['id'] as int) > after)
              .toList(),
        );
      }),
    );

    await _openChat(tester);
    expect(find.text('hello'), findsOneWidget);
    expect(requests, contains('POST /api/conversations/7/read/?'));

    await tester.enterText(
      find.byKey(const ValueKey('chat-draft')),
      'on my way',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('on my way'), findsOneWidget);

    server.add(_message(3, 'see you soon'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('see you soon'), findsOneWidget);
    expect(find.text('on my way'), findsOneWidget);
    expect(requests, contains('GET /api/conversations/7/messages/?after=2'));

    await _closeChat(tester);
    final countAfterClose = requests.length;
    await tester.pump(const Duration(seconds: 12));
    expect(
      requests.length,
      countAfterClose,
      reason: 'polling must stop once the screen closes',
    );
  });

  testWidgets('failed send shows Retry and delivers once on retry', (
    tester,
  ) async {
    var failPosts = true;
    var posts = 0;
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          if (failPosts) throw http.ClientException('Connection closed');
          return _json(_message(5, 'are you close?', mine: true), 201);
        }
        return _json([]);
      }),
    );

    await _openChat(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft')),
      'are you close?',
    );
    // Let the Send button rebuild as enabled before tapping it.
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    failPosts = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('are you close?'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(posts, 2);
    await _closeChat(tester);
  });

  testWidgets('a hire that is no longer active shows the chat as closed', (
    tester,
  ) async {
    GawaGoApi.setClient(
      MockClient(
        (request) async =>
            _json({'detail': "You can't access this conversation."}, 403),
      ),
    );

    await _openChat(tester);

    expect(find.textContaining('This chat is closed'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-draft')), findsNothing);
    await _closeChat(tester);
  });

  testWidgets('a finished job shows its history read only', (tester) async {
    const finished = ChatConversation(
      id: 7,
      jobTitle: 'Deep clean',
      statusLabel: 'Completed',
      otherPartyName: 'Hana Tester',
      otherPartyRole: 'household',
      otherPartyPhotoUrl: '',
      unreadCount: 0,
      readOnly: true,
    );
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.url.path.endsWith('/read/')) {
          return _json({'marked_read': 0});
        }
        return _json([_message(1, 'See you at 8')]);
      }),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatScreen(
          conversation: finished,
          pollInterval: Duration(seconds: 4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('See you at 8'), findsOneWidget);
    expect(
      find.text('This job is finished, so the chat is read only.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-draft')), findsNothing);
    expect(
      ChatConversation.fromJson({'id': 1, 'read_only': true}).readOnly,
      isTrue,
    );
  });
  testWidgets('two chats with the same person show which job each is', (
    tester,
  ) async {
    Map<String, dynamic> hire(int id, String job, Object? last) => {
      'id': id,
      'job_title': job,
      'status_label': 'In progress',
      'other_party': {
        'name': 'Hana Tester',
        'role': 'household',
        'photo_url': '',
      },
      'last_message': last,
      'unread_count': 0,
    };
    GawaGoApi.setClient(
      MockClient(
        (request) async => _json([
          hire(7, 'Deep clean', _message(3, 'on my way', mine: true)),
          hire(8, 'Laundry', null),
        ]),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConversationsView(role: 'worker')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hana Tester'), findsNWidgets(2));
    expect(find.text('Deep clean'), findsOneWidget);
    expect(find.text('Laundry'), findsOneWidget);
    expect(find.text('You: on my way'), findsOneWidget);
  });

  testWidgets('a day divider above the messages; bubbles show just the time', (
    tester,
  ) async {
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.url.path.endsWith('/read/')) {
          return _json({'marked_read': 1});
        }
        return _json(
          request.url.queryParameters['after'] == null
              ? [_message(1, 'hello')]
              : [],
        );
      }),
    );

    await _openChat(tester);
    final sent = DateTime.parse('2026-09-23T08:00:00Z').toLocal();
    expect(find.text('Sep ${sent.day}, 2026'), findsOneWidget);
    expect(find.text(formatClockTime(sent)), findsOneWidget);
    expect(find.textContaining('Hana Tester  '), findsNothing);
    await _closeChat(tester);
  });

  testWidgets('an empty chat names the person and the job', (tester) async {
    GawaGoApi.setClient(MockClient((request) async => _json([])));

    await _openChat(tester);
    expect(
      find.text(
        'No messages yet. Send Hana Tester a message about Deep clean.',
      ),
      findsOneWidget,
    );
    await _closeChat(tester);
  });

  testWidgets('no polling while the app is in the background', (tester) async {
    var gets = 0;
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'GET') gets++;
        return _json([]);
      }),
    );

    await _openChat(tester);
    // Flutter only allows these one step at a time.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    final before = gets;
    await tester.pump(const Duration(seconds: 13));
    expect(gets, before, reason: 'paused: no polls');

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(gets, greaterThan(before), reason: 'catches up on return');
    await _closeChat(tester);
  });
}
