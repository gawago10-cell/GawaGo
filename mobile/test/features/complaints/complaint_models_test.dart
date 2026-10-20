import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/complaints/data/complaint_models.dart';

void main() {
  test('parses a complaint filed by a household against a worker', () {
    final complaint = ComplaintReport.fromJson({
      'id': 11,
      'complainant_username': 'john',
      'respondent_username': 'gawago',
      'job': 19,
      'job_title': 'Test Job at Test Location',
      'complaint_type': 'no_show',
      'description': 'Worker never showed up for the scheduled cleaning.',
      'status': 'submitted',
      'resolution': null,
      'created_at': '2026-09-13T16:10:54.113270+08:00',
    });

    expect(complaint.id, 11);
    expect(complaint.complainantUsername, 'john');
    expect(complaint.respondentUsername, 'gawago');
    expect(complaint.jobId, 19);
    expect(complaint.status, 'submitted');
    expect(complaint.resolution, isEmpty);
  });

  test('tolerates a null job and missing status', () {
    final complaint = ComplaintReport.fromJson({
      'id': 5,
      'complainant_username': 'worker1',
      'complaint_type': 'other',
      'description': 'No job attached.',
    });

    expect(complaint.jobId, isNull);
    expect(complaint.status, 'submitted');
  });

  test(
    'parses the admin-only complainant/respondent account detail when present',
    () {
      final complaint = ComplaintReport.fromJson({
        'id': 12,
        'complainant_username': 'john',
        'respondent_username': 'gawago',
        'complaint_type': 'no_show',
        'description': 'Worker never showed up.',
        'complainant_detail': {
          'username': 'john',
          'display_name': 'John Dela Cruz',
          'role': 'household',
          'average_rating': null,
          'rating_count': 0,
          'location_label': 'Alitao, Tayabas City',
          'member_since': '2026-01-01',
          'phone': '09123456789',
          'email': 'john@example.com',
        },
        'respondent_detail': {
          'username': 'gawago',
          'display_name': 'Gawago Worker',
          'role': 'worker',
          'average_rating': '4.50',
          'rating_count': 12,
          'location_label': 'Alupay, Tayabas City',
          'member_since': '2025-06-15',
          'phone': '',
          'email': 'worker@example.com',
        },
      });

      expect(complaint.complainantDetail?.displayName, 'John Dela Cruz');
      expect(complaint.complainantDetail?.averageRating, isNull);
      expect(complaint.respondentDetail?.displayName, 'Gawago Worker');
      expect(complaint.respondentDetail?.averageRating, 4.5);
      expect(complaint.respondentDetail?.ratingCount, 12);
    },
  );

  test(
    'leaves the account detail null on the household/worker-facing endpoint',
    () {
      final complaint = ComplaintReport.fromJson({
        'id': 13,
        'complainant_username': 'john',
        'respondent_username': 'gawago',
        'complaint_type': 'other',
        'description': 'No admin detail included.',
      });

      expect(complaint.complainantDetail, isNull);
      expect(complaint.respondentDetail, isNull);
    },
  );

  test('admin job label prefers the full job name and location', () {
    final adminView = ComplaintReport.fromJson({
      'id': 13,
      'complaint_type': 'no_show',
      'description': 'Never arrived.',
      'job_title': 'Deep Cleaning at Isabang',
      'job_name': 'Deep Cleaning',
      'job_barangay': 'Purok 2, Isabang, Tayabas City',
    });
    final filerView = ComplaintReport.fromJson({
      'id': 14,
      'complaint_type': 'no_show',
      'description': 'Never arrived.',
      'job_title': 'Deep Cleaning at Isabang',
    });

    expect(
      adminView.adminJobLabel,
      'Deep Cleaning · Purok 2, Isabang, Tayabas City',
    );
    expect(filerView.adminJobLabel, 'Deep Cleaning at Isabang');
  });
}
