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
    required this.workerSlots,
    required this.hiredCount,
    required this.status,
    required this.canReview,
    required this.applications,
    required this.images,
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
  final int workerSlots;
  final int hiredCount;
  final String status;
  final bool canReview;
  final List<HouseholdApplication> applications;
  final List<JobImage> images;

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
      workerSlots: _integer(json['workers_needed'] ?? json['worker_slots']),
      hiredCount: _integer(json['hired_count']),
      status: _text(json['status']),
      canReview: json['can_review'] == true,
      applications: _list(
        json['applications'],
      ).map((item) => HouseholdApplication.fromJson(_map(item))).toList(),
      images: _list(
        json['images'],
      ).map((item) => JobImage.fromJson(_map(item))).toList(),
    );
  }
}

class HouseholdApplication {
  const HouseholdApplication({
    required this.id,
    required this.workerUsername,
    required this.workerName,
    required this.locationLabel,
    required this.status,
    required this.note,
    required this.distanceKm,
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
    required this.routePoints,
  });

  final int id;
  final String workerUsername;
  final String workerName;
  final String locationLabel;
  final String status;
  final String note;
  final double? distanceKm;
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
      workerUsername: _text(json['worker_username']),
      workerName: _text(json['worker_name']),
      locationLabel: _text(json['worker_location_label']),
      status: _text(json['status']),
      note: _text(json['note']),
      distanceKm: _number(json['route_distance_km']),
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
      routePoints: _list(
        json['route_points'],
      ).map(RoutePoint.fromJson).whereType<RoutePoint>().toList(),
    );
  }
}

class RecommendedWorker {
  const RecommendedWorker({
    required this.id,
    required this.username,
    required this.skills,
    required this.verificationStatus,
    required this.distanceLabel,
    required this.distanceKm,
    required this.matchScore,
    required this.ratingLabel,
    required this.workerRate,
    required this.workerLatitude,
    required this.workerLongitude,
    required this.routePoints,
  });

  final int id;
  final String username;
  final List<String> skills;
  final String verificationStatus;
  final String distanceLabel;
  final double? distanceKm;
  final double matchScore;
  final String ratingLabel;
  final String workerRate;
  final double? workerLatitude;
  final double? workerLongitude;
  final List<RoutePoint> routePoints;

  factory RecommendedWorker.fromJson(Map<String, dynamic> json) {
    return RecommendedWorker(
      id: _integer(json['worker_id']),
      username: _text(json['worker_username']),
      skills: _list(json['skills']).map((item) => item.toString()).toList(),
      verificationStatus: _text(json['verification_status']),
      distanceLabel: _text(json['distance_label']),
      distanceKm: _number(json['distance_km']),
      matchScore: _number(json['match_score']) ?? 0,
      ratingLabel: _text(json['rating_label']),
      workerRate: _text(json['worker_rate']),
      workerLatitude: _number(json['worker_latitude']),
      workerLongitude: _number(json['worker_longitude']),
      routePoints: _list(
        json['route_points'],
      ).map(RoutePoint.fromJson).whereType<RoutePoint>().toList(),
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
