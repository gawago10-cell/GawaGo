class WorkerProfile {
  const WorkerProfile({
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.bio,
    required this.skills,
    required this.hourlyRate,
    required this.dailyRate,
    required this.yearsExperience,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.profilePhotoUrl,
    required this.verificationStatus,
    required this.displayRating,
    required this.availabilityWindows,
    required this.weeklyAvailability,
  });

  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String phone;
  final String bio;
  final List<String> skills;
  final double? hourlyRate;
  final double? dailyRate;
  final int yearsExperience;
  final String locationLabel;
  final double? latitude;
  final double? longitude;
  final String profilePhotoUrl;
  final String verificationStatus;
  final String displayRating;
  final List<AvailabilityWindow> availabilityWindows;
  final List<WeeklyAvailability> weeklyAvailability;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

  factory WorkerProfile.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final profile = _map(json['profile']);
    return WorkerProfile(
      username: _text(user['username']),
      email: _text(user['email']),
      firstName: _text(user['first_name']),
      lastName: _text(user['last_name']),
      phone: _text(profile['phone']),
      bio: _text(profile['bio']),
      skills: _strings(profile['skills']),
      hourlyRate: _number(profile['hourly_rate']),
      dailyRate: _number(profile['daily_rate']),
      yearsExperience: _integer(profile['years_experience']),
      locationLabel: _text(profile['location_label']),
      latitude: _number(profile['latitude']),
      longitude: _number(profile['longitude']),
      profilePhotoUrl: _text(profile['profile_photo_url']),
      verificationStatus: _text(profile['verification_status'], 'unverified'),
      displayRating: _text(profile['display_rating'], 'No ratings yet'),
      availabilityWindows: _list(
        profile['availability_windows'],
      ).map((item) => AvailabilityWindow.fromJson(_map(item))).toList(),
      weeklyAvailability: _list(
        profile['weekly_availability'],
      ).map((item) => WeeklyAvailability.fromJson(_map(item))).toList(),
    );
  }
}

class AvailabilityWindow {
  const AvailabilityWindow({
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  final String date;
  final String startTime;
  final String endTime;

  factory AvailabilityWindow.fromJson(Map<String, dynamic> json) {
    return AvailabilityWindow(
      date: _text(json['date']),
      startTime: _text(json['start_time']),
      endTime: _text(json['end_time']),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'start_time': startTime,
    'end_time': endTime,
    'is_available': true,
  };
}

class WeeklyAvailability {
  const WeeklyAvailability({
    required this.weekday,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String label;
  final String startTime;
  final String endTime;

  factory WeeklyAvailability.fromJson(Map<String, dynamic> json) {
    return WeeklyAvailability(
      weekday: _integer(json['weekday']),
      label: _text(json['weekday_label']),
      startTime: _text(json['start_time']),
      endTime: _text(json['end_time']),
    );
  }

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'start_time': startTime,
    'end_time': endTime,
    'is_available': true,
  };
}

class WorkerJob {
  const WorkerJob({
    required this.id,
    required this.title,
    required this.householdUsername,
    required this.householdName,
    required this.jobType,
    required this.requiredSkill,
    required this.schedule,
    required this.description,
    required this.locationLabel,
    required this.serviceRate,
    required this.status,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    required this.routePoints,
    required this.images,
    required this.canApply,
    required this.canAcceptHireRequest,
    required this.canRequestCompletion,
    required this.canReview,
    required this.application,
  });

  final int id;
  final String title;
  final String householdUsername;
  final String householdName;
  final String jobType;
  final String requiredSkill;
  final String schedule;
  final String description;
  final String locationLabel;
  final double serviceRate;
  final String status;
  final double? distanceKm;
  final double? latitude;
  final double? longitude;
  final List<RoutePoint> routePoints;
  final List<JobImage> images;
  final bool canApply;
  final bool canAcceptHireRequest;
  final bool canRequestCompletion;
  final bool canReview;
  final WorkerApplication? application;

  factory WorkerJob.fromJson(Map<String, dynamic> json) {
    final application = json['current_worker_application'];
    return WorkerJob(
      id: _integer(json['id']),
      title: _text(json['title']),
      householdUsername: _text(json['household_username']),
      householdName: _text(json['household_name']),
      jobType: _text(json['job_type']),
      requiredSkill: _text(json['required_skill']),
      schedule: _text(json['schedule']),
      description: _text(json['description']),
      locationLabel: _text(json['location_label']),
      serviceRate: _number(json['service_rate']) ?? 0,
      status: _text(json['status']),
      distanceKm: _number(json['route_distance_km']),
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      routePoints: _list(
        json['route_points'],
      ).map(RoutePoint.fromJson).whereType<RoutePoint>().toList(),
      images: _list(
        json['images'],
      ).map((item) => JobImage.fromJson(_map(item))).toList(),
      canApply: json['can_apply'] == true,
      canAcceptHireRequest: json['can_accept_hire_request'] == true,
      canRequestCompletion: json['can_request_completion'] == true,
      canReview: json['can_review'] == true,
      application: application is Map<String, dynamic>
          ? WorkerApplication.fromJson(application)
          : null,
    );
  }
}

class JobImage {
  const JobImage({required this.id, required this.url});

  final int id;
  final String url;

  factory JobImage.fromJson(Map<String, dynamic> json) {
    return JobImage(
      id: _integer(json['id']),
      url: _text(json['image_url'] ?? json['image']),
    );
  }
}

class GawaGoReview {
  const GawaGoReview({
    required this.id,
    required this.authorUsername,
    required this.authorName,
    required this.targetUsername,
    required this.targetName,
    required this.jobId,
    required this.jobTitle,
    required this.rating,
    required this.feedback,
    required this.createdAt,
  });

  final int id;
  final String authorUsername;
  final String authorName;
  final String targetUsername;
  final String targetName;
  final int? jobId;
  final String jobTitle;
  final double? rating;
  final String feedback;
  final String createdAt;

  factory GawaGoReview.fromJson(Map<String, dynamic> json) {
    return GawaGoReview(
      id: _integer(json['id']),
      authorUsername: _text(json['author_username']),
      authorName: _text(json['author_name'], 'Masked Worker'),
      targetUsername: _text(json['target_username']),
      targetName: _text(json['target_name']),
      jobId: json['job'] == null ? null : _integer(json['job']),
      jobTitle: _text(json['job_title']),
      rating: _number(json['rating']),
      feedback: _text(json['feedback']),
      createdAt: _text(json['created_at']),
    );
  }

  String get displayDate {
    final value = createdDate;
    if (value == null) return createdAt;
    return '${_month(value.month)} ${value.day}, ${value.year}';
  }

  DateTime? get createdDate => parseBackendDateTime(createdAt);
}

class RoutePoint {
  const RoutePoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  static RoutePoint? fromJson(dynamic value) {
    if (value is List && value.length >= 2) {
      final first = _number(value[0]);
      final second = _number(value[1]);
      if (first == null || second == null) return null;
      // Backend route geometry is serialized as [latitude, longitude].
      return RoutePoint(first, second);
    }
    if (value is Map<String, dynamic>) {
      final latitude = _number(value['latitude'] ?? value['lat']);
      final longitude = _number(value['longitude'] ?? value['lng']);
      if (latitude != null && longitude != null) {
        return RoutePoint(latitude, longitude);
      }
    }
    return null;
  }
}

class WorkerApplication {
  const WorkerApplication({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.jobType,
    required this.jobStatus,
    required this.jobSchedule,
    required this.jobScheduleType,
    required this.jobPreferredDate,
    required this.jobPreferredTime,
    required this.jobDescription,
    required this.householdUsername,
    required this.householdName,
    required this.locationLabel,
    required this.serviceRate,
    required this.distanceKm,
    required this.canAcceptHireRequest,
    required this.canRequestCompletion,
    required this.canReview,
    required this.status,
    required this.note,
    required this.appliedAt,
  });

  final int id;
  final int jobId;
  final String jobTitle;
  final String jobType;
  final String jobStatus;
  final String jobSchedule;
  final String jobScheduleType;
  final String jobPreferredDate;
  final String jobPreferredTime;
  final String jobDescription;
  final String householdUsername;
  final String householdName;
  final String locationLabel;
  final double serviceRate;
  final double? distanceKm;
  final bool canAcceptHireRequest;
  final bool canRequestCompletion;
  final bool canReview;
  final String status;
  final String note;
  final String appliedAt;

  factory WorkerApplication.fromJson(Map<String, dynamic> json) {
    return WorkerApplication(
      id: _integer(json['id']),
      jobId: _integer(json['job_id']),
      jobTitle: _text(json['job_title']),
      jobType: _text(json['job_type']),
      jobStatus: _text(json['job_status']),
      jobSchedule: _text(json['job_schedule']),
      jobScheduleType: _text(json['job_schedule_type']),
      jobPreferredDate: _text(json['job_preferred_date']),
      jobPreferredTime: _text(json['job_preferred_time']),
      jobDescription: _text(json['job_description']),
      householdUsername: _text(json['household_username']),
      householdName: _text(json['household_name']),
      locationLabel: _text(json['location_label']),
      serviceRate: _number(json['service_rate']) ?? 0,
      distanceKm: _number(json['route_distance_km']),
      canAcceptHireRequest: json['can_accept_hire_request'] == true,
      canRequestCompletion: json['can_request_completion'] == true,
      canReview: json['can_review'] == true,
      status: _text(json['status']),
      note: _text(json['note']),
      appliedAt: _text(json['applied_at']),
    );
  }
}

class WorkerNotification {
  const WorkerNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.requiresAction,
    required this.jobId,
    required this.applicationId,
    required this.actionType,
    required this.actionUrl,
    required this.actorUsername,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final bool requiresAction;
  final int? jobId;
  final int? applicationId;
  final String actionType;
  final String actionUrl;
  final String actorUsername;
  final String createdAt;

  int? get targetJobId {
    if (jobId != null) return jobId;
    final match = RegExp(r'/jobs/(\d+)').firstMatch(actionUrl);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool get hasDetails => targetJobId != null || message.isNotEmpty;

  DateTime? get createdDate => parseBackendDateTime(createdAt);

  String get displayDate {
    final value = createdDate;
    if (value == null) return createdAt;
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${_month(value.month)} ${value.day}, ${value.year} '
        '$hour:$minute $period';
  }

  factory WorkerNotification.fromJson(Map<String, dynamic> json) {
    return WorkerNotification(
      id: _integer(json['id']),
      title: _text(json['title']),
      message: _text(json['message']),
      type: _text(json['notification_type']),
      isRead: json['is_read'] == true,
      requiresAction: json['requires_action'] == true,
      jobId: json['related_job_id'] == null
          ? null
          : _integer(json['related_job_id']),
      applicationId: json['related_application_id'] == null
          ? null
          : _integer(json['related_application_id']),
      actionType: _text(json['action_type']),
      actionUrl: _text(json['action_url']),
      actorUsername: _text(json['actor_username']),
      createdAt: _text(json['created_at']),
    );
  }
}

DateTime? parseBackendDateTime(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final hasTimezone = RegExp(
    r'(z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final normalized = hasTimezone ? trimmed : '${trimmed}Z';
  return DateTime.tryParse(normalized)?.toLocal();
}

String _month(int value) => const [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value];

class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.status,
    required this.primaryName,
    required this.secondaryName,
    required this.submittedAt,
    required this.reviewNote,
  });

  final int id;
  final String status;
  final String primaryName;
  final String secondaryName;
  final String submittedAt;
  final String reviewNote;

  factory VerificationRequest.fromJson(Map<String, dynamic> json) {
    return VerificationRequest(
      id: _integer(json['id']),
      status: _text(json['status']),
      primaryName: _text(json['primary_id_name']),
      secondaryName: _text(json['secondary_doc_name']),
      submittedAt: _text(json['submitted_at']),
      reviewNote: _text(json['review_note']),
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
List<String> _strings(dynamic value) =>
    _list(value).map((item) => item.toString()).toList();
