class AdminDashboardMetrics {
  const AdminDashboardMetrics({
    required this.openJobs,
    required this.verifiedWorkers,
    required this.completedJobs,
    required this.cancelledJobs,
    required this.activeApplications,
    required this.totalAccounts,
    required this.averageRating,
    required this.pendingVerifications,
    required this.ongoingMatches,
    required this.barangayDemand,
    required this.workerAvailability,
    required this.averageRates,
    required this.ratingDistribution,
  });

  final int openJobs;
  final int verifiedWorkers;
  final int completedJobs;
  final int cancelledJobs;
  final int activeApplications;
  final int totalAccounts;
  final double? averageRating;
  final int pendingVerifications;
  final int ongoingMatches;
  final List<AdminAnalyticsItem> barangayDemand;
  final List<AdminAnalyticsItem> workerAvailability;
  final List<AdminAnalyticsItem> averageRates;
  final List<AdminAnalyticsItem> ratingDistribution;

  factory AdminDashboardMetrics.fromJson(Map<String, dynamic> json) {
    final analytics = _map(json['analytics']);
    final geographic = _map(analytics['geographicAnalytics']);
    final rates = _map(analytics['rateTransparency']);
    final summary = _map(analytics['summary']);
    return AdminDashboardMetrics(
      openJobs: _integer(json['open_jobs']),
      verifiedWorkers: _integer(json['verified_workers']),
      completedJobs: _integer(json['completed_jobs']),
      cancelledJobs: _integer(json['cancelled_jobs']),
      activeApplications: _integer(json['active_applications']),
      totalAccounts: _integer(json['total_accounts']),
      averageRating: _number(json['avg_rating']),
      pendingVerifications: _integer(summary['pendingVerifications']),
      ongoingMatches: _integer(summary['ongoingMatches']),
      barangayDemand: _items(geographic['barangayDemand']),
      workerAvailability: _items(geographic['workerAvailability']),
      averageRates: _items(rates['averageRatesByCategory']),
      ratingDistribution: _items(analytics['ratingDistribution']),
    );
  }
}

class AdminAnalyticsItem {
  const AdminAnalyticsItem({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final double value;
  final String unit;

  factory AdminAnalyticsItem.fromJson(Map<String, dynamic> json) {
    final label = _text(
      json['barangay'] ??
          json['serviceType'] ??
          json['job_type'] ??
          json['rating'] ??
          json['label'],
      'Unspecified',
    );
    final dynamic rawValue =
        json['jobs'] ??
        json['workers'] ??
        json['averageRate'] ??
        json['count'] ??
        json['value'];
    final unit = json.containsKey('averageRate') ? 'PHP' : '';
    return AdminAnalyticsItem(
      label: label,
      value: _number(rawValue) ?? 0,
      unit: unit,
    );
  }
}

class AdminVerificationRequest {
  const AdminVerificationRequest({
    required this.id,
    required this.status,
    required this.accountRole,
    required this.username,
    required this.name,
    required this.email,
    required this.phone,
    required this.location,
    required this.skills,
    required this.primaryDocument,
    required this.secondaryDocument,
    required this.primaryDocumentPath,
    required this.secondaryDocumentPath,
    required this.notes,
    required this.submittedAt,
    required this.reviewNote,
  });

  final int id;
  final String status;
  final String accountRole;
  final String username;
  final String name;
  final String email;
  final String phone;
  final String location;
  final List<String> skills;
  final String primaryDocument;
  final String secondaryDocument;

  /// Authenticated API paths for the two uploaded files. The documents sit
  /// behind IsAuthenticated, so they are fetched with the bearer token
  /// rather than handed straight to Image.network.
  final String primaryDocumentPath;
  final String secondaryDocumentPath;
  final String notes;
  final String submittedAt;
  final String reviewNote;

  factory AdminVerificationRequest.fromJson(Map<String, dynamic> json) {
    return AdminVerificationRequest(
      id: _integer(json['id']),
      status: _text(json['status']),
      accountRole: _text(json['account_role']),
      username: _text(json['worker_username']),
      name: _text(json['worker_name']),
      email: _text(json['worker_email']),
      phone: _text(json['worker_phone']),
      location: _text(json['worker_location_label']),
      skills: _list(
        json['worker_skills'],
      ).map((item) => item.toString()).toList(),
      primaryDocument: _text(json['primary_id_name']),
      secondaryDocument: _text(json['secondary_doc_name']),
      primaryDocumentPath:
          'common/verification-requests/${_integer(json['id'])}/documents/primary/',
      secondaryDocumentPath:
          'common/verification-requests/${_integer(json['id'])}/documents/secondary/',
      notes: _text(json['notes']),
      submittedAt: _text(json['submitted_at']),
      reviewNote: _text(json['review_note']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

List<AdminAnalyticsItem> _items(dynamic value) => _list(
  value,
).whereType<Map<String, dynamic>>().map(AdminAnalyticsItem.fromJson).toList();

String _text(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

double? _number(dynamic value) => value == null
    ? null
    : value is num
    ? value.toDouble()
    : double.tryParse(value.toString());

int _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
