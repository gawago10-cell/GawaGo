import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/signup_validation.dart';

Map<String, String> _filled({Map<String, String> overrides = const {}}) => {
  SignupField.firstName: 'Louise',
  SignupField.lastName: 'Ancaja',
  SignupField.username: 'louise',
  SignupField.email: 'louise@gmail.com',
  SignupField.phone: '9837483765',
  SignupField.streetAddress: 'Alsam Elementary School',
  SignupField.password: 'password1',
  SignupField.confirmPassword: 'password1',
  'hourlyRate': '',
  'dailyRate': '700',
  ...overrides,
};

Map<String, String> _errors({
  bool isWorker = false,
  Map<String, String> overrides = const {},
  String? barangay = 'Alsam Ibaba',
  bool hasLocation = true,
  List<String> skills = const ['Plumbing'],
}) => signupFieldErrors(
  isWorker: isWorker,
  text: _filled(overrides: overrides),
  barangay: barangay,
  hasLocation: hasLocation,
  skills: skills,
);

void main() {
  test('a complete household or worker form has no errors', () {
    expect(_errors(), isEmpty);
    expect(_errors(isWorker: true), isEmpty);
  });

  test('flags only the empty field, in the web form\'s words', () {
    final errors = _errors(overrides: {SignupField.streetAddress: '  '});
    expect(errors, {SignupField.streetAddress: 'Street / house no. is required.'});
  });

  test('flags every empty field at once', () {
    final errors = signupFieldErrors(
      isWorker: true,
      text: const {},
      barangay: null,
      hasLocation: false,
    );
    expect(
      errors.keys.toSet(),
      {
        SignupField.firstName,
        SignupField.lastName,
        SignupField.username,
        SignupField.email,
        SignupField.phone,
        SignupField.streetAddress,
        SignupField.barangay,
        SignupField.location,
        SignupField.rate,
        SignupField.skills,
        SignupField.password,
        SignupField.confirmPassword,
      },
    );
  });

  test('explains a bad email, a short password and a mismatch', () {
    expect(
      _errors(overrides: {SignupField.email: 'louise@gmail'})[SignupField.email],
      contains('complete email'),
    );
    expect(
      _errors(
        overrides: {
          SignupField.password: 'short',
          SignupField.confirmPassword: 'short',
        },
      )[SignupField.password],
      contains('8'),
    );
    expect(
      _errors(overrides: {SignupField.confirmPassword: 'different1'}),
      {SignupField.confirmPassword: 'Passwords do not match.'},
    );
  });

  test('a worker needs a rate, a skill and a typed name for Other', () {
    expect(
      _errors(isWorker: true, overrides: {'dailyRate': ''})[SignupField.rate],
      isNotNull,
    );
    expect(
      _errors(isWorker: true, skills: const [])[SignupField.skills],
      'Choose at least one skill.',
    );
    expect(
      _errors(isWorker: true, skills: const ['Other'])[SignupField.customSkill],
      contains('Type the name'),
    );
  });
}
