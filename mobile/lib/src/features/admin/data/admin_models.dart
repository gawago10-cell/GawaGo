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
    this.totalJobPostings = 0,
    this.verifiedUsers = 0,
    this.hiringSuccessRate = 0,
    this.jobMatchRate = 0,
    this.hiredWorkers = 0,
    this.repeatHires = 0,
    this.applicationTrend = const [],
    this.monthlyJobPostings = const [],
    this.serviceDistribution = const [],
    this.pricingTrends = const [],
  });

  /// Open job postings (the same count as the web dashboard's Open Jobs).
  final int openJobs;
  final int verifiedWorkers;
  final int completedJobs;
  final int cancelledJobs;
  final int activeApplications;

  /// Household and worker accounts (admins are not counted).
  final int totalAccounts;
  final double? averageRating;

  /// Accounts with an ID actually waiting in the review queue.
  final int pendingVerifications;
  final int ongoingMatches;
  final List<AdminAnalyticsItem> barangayDemand;
  final List<AdminAnalyticsItem> workerAvailability;
  final List<AdminAnalyticsItem> averageRates;
  final List<AdminAnalyticsItem> ratingDistribution;

  // Hiring performance and trends (AGENTS.md IV.A), from enhancedAnalytics.
  final int totalJobPostings;
  final int verifiedUsers;
  final double hiringSuccessRate;
  final double jobMatchRate;
  final int hiredWorkers;
  final int repeatHires;
  final List<AdminAnalyticsItem> applicationTrend;
  final List<AdminAnalyticsItem> monthlyJobPostings;
  final List<AdminAnalyticsItem> serviceDistribution;
  final List<AdminAnalyticsItem> pricingTrends;

  factory AdminDashboardMetrics.fromJson(Map<String, dynamic> json) {
    final analytics = _map(json['analytics']);
    final geographic = _map(analytics['geographicAnalytics']);
    final rates = _map(analytics['rateTransparency']);
    final summary = _map(analytics['summary']);
    final enhanced = _map(analytics['enhancedAnalytics']);
    final hiring = _map(enhanced['workerHiringStats']);
    return AdminDashboardMetrics(
      openJobs: _integer(summary['activeJobs'] ?? json['open_jobs']),
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
      // Five star buckets always come back; only buckets with ratings say
      // anything, and an all-zero list should read as "no ratings yet".
      ratingDistribution: _items(
        analytics['ratingDistribution'],
      ).where((item) => item.value > 0).toList(),
      totalJobPostings: _integer(summary['totalJobPostings']),
      verifiedUsers: _integer(summary['verifiedUsers']),
      hiringSuccessRate: _number(enhanced['hiringSuccessRate']) ?? 0,
      jobMatchRate: _number(enhanced['jobMatchRate']) ?? 0,
      hiredWorkers: _integer(hiring['hiredWorkers']),
      repeatHires: _integer(hiring['repeatHires']),
      applicationTrend: _items(enhanced['applicationTrends']),
      monthlyJobPostings: _items(analytics['monthlyJobRequests']),
      serviceDistribution: _items(
        analytics['serviceAnalytics'],
      ).where((item) => item.value > 0).toList(),
      pricingTrends: _items(rates['pricingTrends']),
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

  /// Reads every row shape the dashboard sends: barangay counts, rate rows
  /// (`skill`/`averageRate`), rating buckets (`stars`/`count`), monthly rows
  /// (`month`/`requests` or `applications`) and service rows
  /// (`service`/`requests`).
  factory AdminAnalyticsItem.fromJson(Map<String, dynamic> json) {
    final label = _text(
      json['barangay'] ??
          json['skill'] ??
          json['service'] ??
          json['stars'] ??
          json['month'] ??
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
        json['requests'] ??
        json['applications'] ??
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

/// One worker credential in the admin review queue
/// (GET /accounts/admin/certificates/).
class AdminCertificate {
  const AdminCertificate({
    required this.id,
    required this.workerUsername,
    required this.workerName,
    required this.workerLocation,
    required this.typeLabel,
    required this.name,
    required this.issuer,
    required this.issueDate,
    required this.expiryDate,
    required this.fileUrl,
    required this.fileType,
    required this.status,
    required this.notes,
    required this.submittedAt,
  });

  final int id;
  final String workerUsername;
  final String workerName;
  final String workerLocation;
  final String typeLabel;
  final String name;
  final String issuer;
  final String issueDate;
  final String expiryDate;
  final String fileUrl;

  /// "image", "pdf" or "file".
  final String fileType;

  /// "pending", "approved" or "rejected".
  final String status;
  final String notes;
  final String submittedAt;

  String get statusLabel => switch (status) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending Review',
  };

  factory AdminCertificate.fromJson(Map<String, dynamic> json) {
    return AdminCertificate(
      id: _integer(json['id']),
      workerUsername: _text(json['worker_username']),
      workerName: _text(json['worker_name'] ?? json['worker_username']),
      workerLocation: _text(json['worker_location_label']),
      typeLabel: _text(json['certificate_type_label']),
      name: _text(json['certificate_name']),
      issuer: _text(json['issuer']),
      issueDate: _text(json['issue_date'] ?? ''),
      expiryDate: _text(json['expiry_date'] ?? ''),
      fileUrl: _text(json['certificate_file_url'] ?? ''),
      fileType: _text(json['certificate_file_type'] ?? ''),
      status: _text(json['verification_status'], 'pending'),
      notes: _text(json['verification_notes']),
      submittedAt: _text(json['created_at']),
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
