import '../constants/gawago_options.dart';

/// Keys for the sign-up form's fields, in on-screen order.
abstract final class SignupField {
  static const firstName = 'firstName';
  static const lastName = 'lastName';
  static const username = 'username';
  static const email = 'email';
  static const phone = 'phone';
  static const streetAddress = 'streetAddress';
  static const barangay = 'barangay';
  static const location = 'location';
  static const rate = 'rate';
  static const skills = 'skills';
  static const customSkill = 'customSkill';
  static const password = 'password';
  static const confirmPassword = 'confirmPassword';
}

/// Same check as the web form (EMAIL_ADDRESS_PATTERN in appConstants.js).
final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

const _requiredLabels = {
  SignupField.firstName: 'First name',
  SignupField.lastName: 'Last name',
  SignupField.username: 'Username',
  SignupField.email: 'Email',
  SignupField.phone: 'Phone number',
  SignupField.streetAddress: 'Street / house no.',
  SignupField.password: 'Password',
  SignupField.confirmPassword: 'Confirm password',
};

/// Each sign-up field's problem, keyed by [SignupField], or an empty map when
/// the form can be sent. The rules and wording follow the web form
/// (frontend/src/utils/registrationValidation.js) so both apps say the same
/// thing; mobile also asks every account for a map pin and a worker for a
/// rate, as it did before.
Map<String, String> signupFieldErrors({
  required bool isWorker,
  required Map<String, String> text,
  required String? barangay,
  required bool hasLocation,
  Iterable<String> skills = const [],
}) {
  String value(String key) => (text[key] ?? '').trim();
  final errors = <String, String>{};

  for (final entry in _requiredLabels.entries) {
    if (value(entry.key).isEmpty) {
      errors[entry.key] = '${entry.value} is required.';
    }
  }
  if (!errors.containsKey(SignupField.email) &&
      !_emailPattern.hasMatch(value(SignupField.email))) {
    errors[SignupField.email] =
        'Enter a complete email address, e.g. juan@example.com.';
  }
  if (barangay == null || barangay.isEmpty) {
    errors[SignupField.barangay] = 'Barangay is required.';
  }
  if (!hasLocation) {
    errors[SignupField.location] = isWorker
        ? 'Pin where you live on the map, or use your current location. '
              'Households see your distance from this point.'
        : 'Pin where you live on the map, or use your current location.';
  }
  if (isWorker) {
    final hourly = double.tryParse(value('hourlyRate')) ?? 0;
    final daily = double.tryParse(value('dailyRate')) ?? 0;
    if (hourly <= 0 && daily <= 0) {
      errors[SignupField.rate] = 'Enter an hourly or a daily rate.';
    }
    final skillsProblem = workerSkillsProblem(
      skills,
      text[SignupField.customSkill] ?? '',
    );
    if (skillsProblem != null) {
      final aboutTypedSkill = skills.any(isOtherSkillChoice) &&
          skillsProblem.startsWith('Type the name');
      errors[aboutTypedSkill ? SignupField.customSkill : SignupField.skills] =
          skillsProblem;
    }
  }
  final password = text[SignupField.password] ?? '';
  if (!errors.containsKey(SignupField.password) && password.length < 8) {
    errors[SignupField.password] = 'Password must be at least 8 characters.';
  }
  if (!errors.containsKey(SignupField.password) &&
      !errors.containsKey(SignupField.confirmPassword) &&
      password != (text[SignupField.confirmPassword] ?? '')) {
    errors[SignupField.confirmPassword] = 'Passwords do not match.';
  }
  return errors;
}
