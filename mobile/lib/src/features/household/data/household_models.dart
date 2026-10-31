import '../../worker/data/worker_models.dart';

class HouseholdProfile {
  const HouseholdProfile({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.verificationStatus,
    this.verificationRequestStatus = '',
    required this.profilePhotoUrl,
  });

  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String locationLabel;
  final double? latitude;
  final double? longitude;
  final String verificationStatus;

  /// Status of the latest submitted verification request ('' when none),
  /// so "Under Review" means an ID was actually submitted -- new profiles
  /// default to verification_status "pending" regardless.
  final String verificationRequestStatus;
  final String profilePhotoUrl;

  String get fullName {
    final value = '$firstName $lastName'.trim();
    return value.isEmpty ? username : value;
  }

  factory HouseholdProfile.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final profile = _map(json['profile']);
    return HouseholdProfile(
      username: _text(user['username']),
      firstName: _text(user['first_name']),
      lastName: _text(user['last_name']),
      email: _text(user['email']),
      phone: _text(profile['phone']),
      locationLabel: _text(profile['location_label']),
      latitude: _number(profile['latitude']),
      longitude: _number(profile['longitude']),
      verificationStatus: _text(profile['verification_status'], 'unverified'),
      verificationRequestStatus: profile['verification_request'] is Map
          ? _text((profile['verification_request'] as Map)['status'])
          : '',
      profilePhotoUrl: _text(profile['profile_photo_url']),
    );
  }
}

class HouseholdJob {
  const HouseholdJob({
    required this.id,
    required this.householdUsername,
    required this.title,
    required this.jobType,
    required this.requiredSkill,
    required this.schedule,
    required this.description,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.serviceRate,
    this.rateTypeLabel = 'Per Day',
    required this.workerSlots,
    required this.hiredCount,
    required this.status,
    this.statusLabel = '',
    required this.canReview,
    this.canMarkDone = false,
    this.markDoneNote = '',
    required this.applications,
    required this.images,
    required this.jobStartDate,
    required this.jobEndDate,
    required this.estimatedWorkingDays,
    required this.geographicBoundary,
  });

  final int id;
  final String householdUsername;
  final String title;
  final String jobType;
  final String requiredSkill;
  final String schedule;
  final String description;
  final String locationLabel;
  final double latitude;
  final double longitude;
  final double serviceRate;

  /// What serviceRate is per: "Per Day", "Per Hour" or "Fixed Rate".
  final String rateTypeLabel;
  final int workerSlots;
  final int hiredCount;
  final String status;

  /// The backend's own wording for `status` (it owns status labels).
  final String statusLabel;
  final bool canReview;

  /// The household can mark this job done now (backend `can_mark_done`).
  final bool canMarkDone;

  /// Why "Mark as done" isn't available yet, e.g. the start date; "" if it is.
  final String markDoneNote;
  final List<HouseholdApplication> applications;
  final List<JobImage> images;
  final String? jobStartDate;
  final String? jobEndDate;
  final int? estimatedWorkingDays;
  final String geographicBoundary;

  factory HouseholdJob.fromJson(Map<String, dynamic> json) {
    return HouseholdJob(
      id: _integer(json['id']),
      householdUsername: _text(json['household_username']),
      title: _text(json['title']),
      jobType: _text(json['job_type']),
      requiredSkill: _text(json['required_skill']),
      schedule: _text(json['schedule']),
      description: _text(json['description']),
      locationLabel: _text(json['location_label']),
      latitude: _number(json['latitude']) ?? 0,
      longitude: _number(json['longitude']) ?? 0,
      serviceRate: _number(json['service_rate']) ?? 0,
      rateTypeLabel: _text(
        json['rate_type_label'] ?? json['job_rate_type_label'],
        'Per Day',
      ),
      workerSlots: _integer(json['workers_needed'] ?? json['worker_slots']),
      hiredCount: _integer(json['hired_count']),
      status: _text(json['status']),
      statusLabel: _text(json['status_label'] ?? ''),
      canReview: json['can_review'] == true,
      canMarkDone: json['can_mark_done'] == true,
      markDoneNote: _text(json['mark_done_note'] ?? ''),
      applications: _list(
        json['applications'],
      ).map((item) => HouseholdApplication.fromJson(_map(item))).toList(),
      images: _list(
        json['images'],
      ).map((item) => JobImage.fromJson(_map(item))).toList(),
      jobStartDate: json['job_start_date'] as String?,
      jobEndDate: json['job_end_date'] as String?,
      estimatedWorkingDays: json['estimated_working_days'] == null
          ? null
          : _integer(json['estimated_working_days']),
      geographicBoundary: _text(json['geographic_boundary'], '1km'),
    );
  }
}

class HouseholdApplication {
  const HouseholdApplication({
    required this.id,
    required this.workerId,
    required this.workerUsername,
    required this.workerName,
    required this.locationLabel,
    required this.status,
    required this.statusStage,
    required this.statusLabel,
    required this.note,
    required this.distanceKm,
    this.distanceLabel = '',
    required this.workerLatitude,
    required this.workerLongitude,
    required this.workerVerificationStatus,
    required this.workerRatingLabel,
    required this.workerBio,
    required this.workerYearsExperience,
    required this.workerProfilePhotoUrl,
    required this.workerSkills,
    required this.workerHourlyRate,
    required this.workerDailyRate,
    required this.workerRatingCount,
    required this.workerCompletedJobs,
    required this.workerMatchScore,
    required this.appliedAt,
    required this.routePoints,
    this.householdCanReview = false,
  });

  final int id;
  final int workerId;
  final String workerUsername;
  final String workerName;
  final String locationLabel;
  final String status;

  /// Whether this household can still review this particular worker
  /// (backend `household_can_review`). The job's canReview only says some
  /// worker is left, which on a multi-worker job is not enough to pick one.
  final bool householdCanReview;

  /// Canonical stage/label from apps/jobs/statuses.py -- see the matching
  /// fields on WorkerApplication for why this replaces mapping the raw
  /// status locally.
  final String statusStage;
  final String statusLabel;
  final String note;
  final double? distanceKm;

  /// Server-rounded road distance, e.g. "2.3 km away".
  final String distanceLabel;

  /// Null only when the worker has not pinned a location on their profile;
  /// the API sends it (and [routePoints]) for any applicant, hired or not.
  final double? workerLatitude;
  final double? workerLongitude;
  final String workerVerificationStatus;
  final String workerRatingLabel;
  final String workerBio;
  final int workerYearsExperience;
  final String workerProfilePhotoUrl;
  final List<String> workerSkills;
  final double? workerHourlyRate;
  final double? workerDailyRate;
  final int workerRatingCount;
  final int workerCompletedJobs;

  /// The AI content-based fit (0-1) for this applicant, the same scale as the
  /// recommended-worker cards; null when the backend could not score them.
  /// The list itself arrives in Smart Matching's rule order.
  final double? workerMatchScore;
  final String appliedAt;
  final List<RoutePoint> routePoints;

  String get workerRateLabel {
    if (workerDailyRate != null && workerDailyRate! > 0) {
      return 'PHP ${workerDailyRate!.toStringAsFixed(2)} / Per Day';
    }
    if (workerHourlyRate != null && workerHourlyRate! > 0) {
      return 'PHP ${workerHourlyRate!.toStringAsFixed(2)} / Per Hour';
    }
    return '';
  }

  factory HouseholdApplication.fromJson(Map<String, dynamic> json) {
    return HouseholdApplication(
      id: _integer(json['id']),
      workerId: _integer(json['worker']),
      workerUsername: _text(json['worker_username']),
      workerName: _text(json['worker_name']),
      locationLabel: _text(json['worker_location_label']),
      status: _text(json['status']),
      statusStage: _text(json['status_stage']),
      statusLabel: _text(json['status_label']),
      note: _text(json['note']),
      distanceKm: _number(json['route_distance_km']),
      distanceLabel: _text(json['distance_label']),
      workerLatitude: _number(json['worker_latitude']),
      workerLongitude: _number(json['worker_longitude']),
      workerVerificationStatus: _text(json['worker_verification_status']),
      workerRatingLabel: _text(json['worker_rating_label'], 'No ratings yet'),
      workerBio: _text(json['worker_bio']),
      workerYearsExperience: _integer(json['worker_years_experience']),
      workerProfilePhotoUrl: _text(json['worker_profile_photo_url']),
      workerSkills: _list(
        json['worker_skills'],
      ).map((item) => item.toString()).toList(),
      workerHourlyRate: _number(json['worker_hourly_rate']),
      workerDailyRate: _number(json['worker_daily_rate']),
      workerRatingCount: _integer(json['worker_rating_count']),
      workerCompletedJobs: _integer(json['worker_completed_jobs']),
      workerMatchScore: _number(json['worker_match_score']),
      appliedAt: _text(json['applied_at']),
      routePoints: _list(
        json['route_points'],
      ).map(RoutePoint.fromJson).whereType<RoutePoint>().toList(),
      householdCanReview: json['household_can_review'] == true,
    );
  }
}

/// One finished job on a worker's public employment record, as a household
/// reads it off that worker's profile before hiring.
class WorkerJobHistoryEntry {
  const WorkerJobHistoryEntry({
    required this.id,
    required this.title,
    required this.jobType,
    required this.householdName,
    required this.locationLabel,
    required this.completedAt,
    required this.jobStartDate,
    required this.jobEndDate,
    this.skillRatings = const [],
  });

  final int id;
  final String title;
  final String jobType;
  final String householdName;
  final String locationLabel;
  final String completedAt;
  final String jobStartDate;
  final String jobEndDate;
  final List<JobSkillRating> skillRatings;

  /// Prefers the confirmed completion date; older records predate that field
  /// being set, so fall back to the scheduled period and then to nothing
  /// rather than printing a placeholder date.
  String get periodLabel {
    if (completedAt.isNotEmpty) {
      final parsed = DateTime.tryParse(completedAt);
      if (parsed != null) {
        final local = parsed.toLocal();
        return 'Completed ${local.year}-'
            '${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')}';
      }
    }
    if (jobStartDate.isNotEmpty && jobEndDate.isNotEmpty) {
      return '$jobStartDate to $jobEndDate';
    }
    if (jobStartDate.isNotEmpty) return jobStartDate;
    return '';
  }

  factory WorkerJobHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WorkerJobHistoryEntry(
      id: _integer(json['id']),
      title: _text(json['title']),
      jobType: _text(json['job_type']),
      householdName: _text(json['household_name']),
      locationLabel: _text(json['location_label']),
      completedAt: _text(json['completed_at'] ?? ''),
      jobStartDate: _text(json['job_start_date'] ?? ''),
      jobEndDate: _text(json['job_end_date'] ?? ''),
      skillRatings: JobSkillRating.listFromJson(json['skill_ratings']),
    );
  }
}

class RecommendedWorker {
  const RecommendedWorker({
    required this.id,
    required this.username,
    required this.name,
    required this.locationLabel,
    required this.approximateLatitude,
    required this.approximateLongitude,
    required this.bio,
    required this.profilePhotoUrl,
    required this.ratingCount,
    required this.completedJobs,
    required this.skills,
    required this.matchesSkill,
    required this.verificationStatus,
    required this.distanceLabel,
    required this.distanceKm,
    required this.matchScore,
    required this.ratingLabel,
    required this.workerRate,
    required this.aiScore,
    required this.skillContribution,
    required this.proximityContribution,
    required this.exactSkillMatch,
  });

  final int id;
  final String username;
  final String name;
  final String locationLabel;

  /// The worker's home snapped to a ~1 km grid, which is all this browse
  /// list carries: it scores every candidate in range, most of whom never
  /// apply. Null when they have saved no location. Once a worker applies,
  /// their application carries the exact point and the route.
  final double? approximateLatitude;
  final double? approximateLongitude;
  final String bio;
  final String profilePhotoUrl;
  final int ratingCount;
  final int completedJobs;
  final List<String> skills;
  final bool matchesSkill;
  final String verificationStatus;
  final String distanceLabel;
  final double? distanceKm;
  final double matchScore;
  final String ratingLabel;
  final String workerRate;
  final double aiScore;
  final double skillContribution;
  final double proximityContribution;
  final bool exactSkillMatch;

  String get displayName => name.isNotEmpty ? name : username;

  /// Skill's share of the AI score, as a whole percent; null when the
  /// recommender returned no contribution breakdown to explain.
  int? get skillSharePercent {
    final total = skillContribution + proximityContribution;
    if (total <= 0) return null;
    return (skillContribution / total * 100).round();
  }

  factory RecommendedWorker.fromJson(Map<String, dynamic> json) {
    return RecommendedWorker(
      id: _integer(json['worker_id']),
      username: _text(json['worker_username']),
      name: _text(json['worker_name']),
      locationLabel: _text(json['worker_location_label']),
      approximateLatitude: _number(json['worker_approximate_latitude']),
      approximateLongitude: _number(json['worker_approximate_longitude']),
      bio: _text(json['worker_bio']),
      profilePhotoUrl: _text(json['worker_profile_photo_url']),
      ratingCount: _integer(json['worker_rating_count']),
      completedJobs: _integer(json['worker_completed_jobs']),
      skills: _list(json['skills']).map((item) => item.toString()).toList(),
      matchesSkill: json['matches_skill'] == true,
      verificationStatus: _text(json['verification_status']),
      distanceLabel: _text(json['distance_label']),
      distanceKm: _number(json['distance_km']),
      matchScore: _number(json['match_score']) ?? 0,
      ratingLabel: _text(json['rating_label']),
      workerRate: _text(json['worker_rate']),
      aiScore: _number(json['ai_score']) ?? 0,
      skillContribution: _number(json['skill_contribution']) ?? 0,
      proximityContribution: _number(json['proximity_contribution']) ?? 0,
      exactSkillMatch: json['exact_skill_match'] == true,
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};
List<dynamic> _list(dynamic value) => value is List ? value : const [];
String _text(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;
double? _number(dynamic value) => value == null
    ? null
    : value is num
    ? value.toDouble()
    : double.tryParse(value.toString());
int _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
