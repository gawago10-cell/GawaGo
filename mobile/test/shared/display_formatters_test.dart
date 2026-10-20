import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';

void main() {
  group('statusText prefers the backend label', () {
    test('shows the backend wording when it sent one', () {
      // The backend calls an assigned job "In progress"; title-casing the raw
      // status here would read "Assigned", which is what web/mobile/API used
      // to disagree about.
      expect(statusText('In progress', 'assigned'), 'In progress');
      expect(
        statusText('Awaiting confirmation', 'completion_requested'),
        'Awaiting confirmation',
      );
    });

    test('falls back to the raw status when no label was sent', () {
      expect(statusText('', 'assigned'), 'Assigned');
      expect(statusText('   ', 'completion_requested'), 'Completion Requested');
      expect(statusText('', ''), 'Open');
    });
  });

  group('sanitizePhilippinesPhone matches the web client', () {
    test('strips non-digits and a leading zero, caps at 10 digits', () {
      expect(sanitizePhilippinesPhone('0917 123 4567'), '9171234567');
      // The leading zero strips off "0917..."; a +63 prefix has no leading
      // zero to strip, so its country code survives as ordinary digits.
      expect(sanitizePhilippinesPhone('+63 917 123 4567'), '6391712345');
      expect(sanitizePhilippinesPhone('09171234567890'), '9171234567');
      expect(sanitizePhilippinesPhone(''), '');
    });
  });

  group('formatJobDate', () {
    test('formats an ISO date like the web client', () {
      expect(formatJobDate('2026-10-04'), 'Oct 4, 2026');
    });

    test('falls back when there is nothing to format', () {
      expect(formatJobDate(null), 'Not set');
      expect(formatJobDate(''), 'Not set');
    });
  });

  test('formats backend status values for users', () {
    expect(formatStatus('hire_requested'), 'Hire Requested');
    expect(formatStatus('completion_requested'), 'Completion Requested');
    expect(formatStatus('in-progress'), 'In Progress');
  });

  test('formats ISO timestamps as readable local dates', () {
    final formatted = formatLocalDateTime('2026-06-10T09:30:00+08:00');

    expect(formatted, contains('Jun 10, 2026'));
    expect(formatted, isNot(contains('T09:30:00')));
  });

  test('preserves schedules that are already human-readable', () {
    expect(
      formatDateOrText('One-Time on June 15 at 10:00 AM'),
      'One-Time on June 15 at 10:00 AM',
    );
  });

  test('maps application statuses to the web app vocabulary', () {
    expect(applicationStatusLabel('pending'), 'Applied');
    expect(applicationStatusLabel('hired'), 'Hired');
    expect(applicationStatusLabel('rejected'), 'Rejected');
    // Displayed as Hired, not Completed, to avoid confusion with job
    // completion (matches frontend/src/utils/jobUtils.js).
    expect(applicationStatusLabel('completed'), 'Hired');
    expect(applicationStatusLabel('closed'), 'Closed');
  });

  test('recent timestamps read as "just now"', () {
    expect(_ago(const Duration(seconds: 5)), 'just now');
  });

  test('time-ago walks up to the largest unit that still fits', () {
    expect(_ago(const Duration(minutes: 3)), '3 minutes ago');
    expect(_ago(const Duration(hours: 5)), '5 hours ago');
    expect(_ago(const Duration(days: 3)), '3 days ago');
  });

  test('singular time-ago units drop the plural s', () {
    expect(_ago(const Duration(minutes: 1, seconds: 3)), '1 minute ago');
    expect(_ago(const Duration(hours: 1, minutes: 2)), '1 hour ago');
  });

  test('an unparseable timestamp yields an empty time-ago label', () {
    expect(formatTimeAgo(''), '');
    expect(formatTimeAgo('not a date'), '');
  });
}

String _ago(Duration elapsed) =>
    formatTimeAgo(DateTime.now().toUtc().subtract(elapsed).toIso8601String());
