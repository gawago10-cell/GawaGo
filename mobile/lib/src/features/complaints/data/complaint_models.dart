/// Mirrors the Complaint envelope from backend/apps/complaints/serializers.py.
///
/// "Report an Issue" -- an incident filed against a specific job's other
/// party (household reports a worker, or vice versa), reviewed by admin.
/// Distinct from the activity report: this tracks one case, not a summary.
class ComplaintReport {
  const ComplaintReport({
    required this.id,
    required this.complainantUsername,
    required this.respondentUsername,
    required this.jobId,
    required this.jobTitle,
    required this.complaintType,
    required this.description,
    required this.status,
    required this.resolution,
    required this.createdAt,
    this.evidenceUrls = const [],
    this.respondentIsBlocked = false,
    this.respondentBlockedUntil,
    this.complainantDetail,
    this.respondentDetail,
  });

  final int id;
  final String complainantUsername;
  final String respondentUsername;
  final int? jobId;
  final String jobTitle;
  final String complaintType;
  final String description;
  final String status;
  final String resolution;
  final String createdAt;

  /// Admin-only account context (`ComplaintAdminSerializer`'s
  /// complainant_detail/respondent_detail) -- null on the household/worker
  /// facing endpoints, which never receive these fields.
  final ComplaintPartyDetail? complainantDetail;
  final ComplaintPartyDetail? respondentDetail;

  /// Photos the filer attached so admin can see what happened.
  final List<String> evidenceUrls;

  /// Whether the reported account is currently suspended.
  final bool respondentIsBlocked;

  /// When a timed suspension lifts. Null while blocked means the block is
  /// permanent; null while not blocked just means there's no suspension.
  final DateTime? respondentBlockedUntil;

  /// Human-readable state for the admin queue's account-action row.
  String get suspensionLabel {
    if (!respondentIsBlocked) return '';
    final until = respondentBlockedUntil;
    if (until == null) return 'Account blocked (permanent)';
    final local = until.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    return 'Suspended until $date';
  }

  factory ComplaintReport.fromJson(Map<String, dynamic> json) {
    return ComplaintReport(
      id: _integer(json['id']),
      complainantUsername: _text(json['complainant_username']),
      respondentUsername: _text(json['respondent_username']),
      jobId: json['job'] == null ? null : _integer(json['job']),
      jobTitle: _text(json['job_title']),
      complaintType: _text(json['complaint_type']),
      description: _text(json['description']),
      status: _text(json['status'], 'submitted'),
      resolution: _text(json['resolution']),
      createdAt: _text(json['created_at']),
      evidenceUrls: (json['evidence'] as List<dynamic>? ?? const [])
          .map((item) => _text((item as Map<String, dynamic>)['image_url']))
          .where((url) => url.isNotEmpty)
          .toList(),
      respondentIsBlocked: json['respondent_is_blocked'] == true,
      respondentBlockedUntil: DateTime.tryParse(
        _text(json['respondent_blocked_until']),
      ),
      complainantDetail: ComplaintPartyDetail.fromJson(
        json['complainant_detail'] as Map<String, dynamic>?,
      ),
      respondentDetail: ComplaintPartyDetail.fromJson(
        json['respondent_detail'] as Map<String, dynamic>?,
      ),
    );
  }
}

/// Mirrors `_party_detail()` in backend/apps/complaints/serializers.py --
/// only present when the admin queue's `ComplaintAdminSerializer` is used.
class ComplaintPartyDetail {
  const ComplaintPartyDetail({
    required this.displayName,
    required this.role,
    required this.averageRating,
    required this.ratingCount,
    required this.locationLabel,
    required this.memberSince,
    required this.phone,
    required this.email,
  });

  final String displayName;
  final String role;
  final double? averageRating;
  final int ratingCount;
  final String locationLabel;
  final String memberSince;
  final String phone;
  final String email;

  static ComplaintPartyDetail? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rating = json['average_rating'];
    return ComplaintPartyDetail(
      displayName: _text(json['display_name']),
      role: _text(json['role']),
      averageRating: rating == null ? null : double.tryParse(rating.toString()),
      ratingCount: _integer(json['rating_count']),
      locationLabel: _text(json['location_label']),
      memberSince: _text(json['member_since']),
      phone: _text(json['phone']),
      email: _text(json['email']),
    );
  }
}

const complaintTypeLabels = {
  'payment_issue': 'Payment Issue',
  'quality_of_work': 'Quality of Work',
  'no_show': 'No Show',
  'safety_concern': 'Safety Concern',
  'behavior': 'Inappropriate Behavior',
  'other': 'Other',
};

const complaintStatusLabels = {
  'submitted': 'Submitted',
  'under_review': 'Under Review',
  'resolved': 'Resolved',
  'closed': 'Closed',
};

String _text(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

int _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
