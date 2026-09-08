import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';

void main() {
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
}
