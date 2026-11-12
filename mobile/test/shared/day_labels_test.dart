import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';

void main() {
  final now = DateTime(2026, 11, 12, 21);

  test('notifications sit under Today, Yesterday or Earlier', () {
    expect(
      notificationDayGroup(DateTime(2026, 11, 12, 0, 5), now: now),
      'Today',
    );
    expect(
      notificationDayGroup(DateTime(2026, 11, 11, 23, 59), now: now),
      'Yesterday',
    );
    expect(
      notificationDayGroup(DateTime(2026, 11, 1, 3, 14), now: now),
      'Earlier',
    );
    expect(notificationDayGroup(null, now: now), 'Earlier');
  });

  test('chat days and times read like the website', () {
    expect(chatDayLabel(DateTime(2026, 11, 12, 8), now: now), 'Today');
    expect(chatDayLabel(DateTime(2026, 11, 11, 9, 5), now: now), 'Yesterday');
    expect(chatDayLabel(DateTime(2026, 11, 1, 3), now: now), 'Nov 1, 2026');
    expect(chatDayLabel(null, now: now), '');
    expect(formatClockTime(DateTime(2026, 11, 11, 9, 5)), '9:05 AM');
    expect(formatClockTime(DateTime(2026, 11, 11, 0, 30)), '12:30 AM');
    expect(formatClockTime(DateTime(2026, 11, 11, 23, 16)), '11:16 PM');
  });

  test('the verified screen says when it was approved', () {
    final approved = VerificationRequest.fromJson({
      'id': 1,
      'status': 'verified',
      'primary_id_name': 'National ID',
      'secondary_doc_name': 'Barangay clearance',
      'submitted_at': '2026-10-19T10:00:00+08:00',
      'reviewed_at': '2026-10-20T08:15:00+08:00',
      'review_note': '',
    });
    final local = DateTime.parse('2026-10-20T08:15:00+08:00').toLocal();
    expect(approved.approvedOnSentence, 'Approved on Oct ${local.day}, 2026. ');
    final pending = VerificationRequest.fromJson({
      'id': 2,
      'status': 'pending',
    });
    expect(pending.approvedOnSentence, '');
  });
}
