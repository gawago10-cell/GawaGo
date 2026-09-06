import '../../../core/api/gawago_api.dart';
import 'worker_models.dart';

class WorkerRepository {
  const WorkerRepository();

  Future<WorkerProfile> getProfile() async {
    return WorkerProfile.fromJson(await GawaGoApi.get('/accounts/me/'));
  }

  Future<WorkerProfile> updateProfile(
    Map<String, dynamic> values, {
    String? profilePhotoPath,
  }) async {
    final response = profilePhotoPath == null
        ? await GawaGoApi.patch('/accounts/me/', body: values)
        : await GawaGoApi.multipartPatch(
            '/accounts/me/',
            fields: values.map(
              (key, value) => MapEntry(key, value?.toString() ?? ''),
            ),
            files: {'profile_photo': profilePhotoPath},
          );
    return WorkerProfile.fromJson(response);
  }

  Future<List<WorkerJob>> getJobs({String? skill, String? location}) async {
    final query = <String, String>{'status': 'open'};
    if (skill != null && skill.isNotEmpty) query['job_type'] = skill;
    if (location != null && location.isNotEmpty) query['location'] = location;
    final uri = Uri(path: '/jobs/', queryParameters: query);
    final data = await GawaGoApi.getList(uri.toString());
    return data.map((item) => WorkerJob.fromJson(item)).toList();
  }

  Future<WorkerJob> getJob(int id) async {
    return WorkerJob.fromJson(await GawaGoApi.get('/jobs/$id/'));
  }

  Future<void> apply(int jobId, String note) async {
    await GawaGoApi.post('/jobs/$jobId/apply/', body: {'note': note});
  }

  Future<List<WorkerApplication>> getApplications() async {
    final data = await GawaGoApi.getList('/jobs/applications/');
    return data.map((item) => WorkerApplication.fromJson(item)).toList();
  }

  Future<void> decideHireRequest(int applicationId, String decision) async {
    await GawaGoApi.patch(
      '/jobs/applications/$applicationId/decision/',
      body: {'decision': decision},
    );
  }

  Future<void> requestCompletion(int jobId, String note) async {
    await GawaGoApi.post(
      '/jobs/$jobId/request-completion/',
      body: {'note': note},
    );
  }

  Future<void> reviewHousehold(
    WorkerJob job, {
    required double rating,
    required String feedback,
  }) async {
    await GawaGoApi.post(
      '/reviews/',
      body: {
        'target_username': job.householdUsername,
        'job_id': job.id,
        'job_title': job.title,
        'rating': rating,
        'feedback': feedback,
      },
    );
  }

  Future<List<GawaGoReview>> getReceivedReviews() async {
    final data = await GawaGoApi.getList('/reviews/');
    return data.map((item) => GawaGoReview.fromJson(item)).toList();
  }

  Future<List<GawaGoReview>> getGivenReviews() async {
    final profile = await getProfile();
    final data = await GawaGoApi.getList(
      '/reviews/?author_username=${Uri.encodeQueryComponent(profile.username)}',
    );
    return data.map((item) => GawaGoReview.fromJson(item)).toList();
  }

  Future<List<GawaGoReview>> getHouseholdReviews(String username) async {
    final data = await GawaGoApi.getList(
      '/reviews/?target_username=${Uri.encodeQueryComponent(username)}',
    );
    return data.map((item) => GawaGoReview.fromJson(item)).toList();
  }

  Future<void> saveWeeklyAvailability(List<WeeklyAvailability> windows) async {
    await GawaGoApi.put(
      '/accounts/me/weekly-availability/',
      body: {
        'weekly_availability': windows.map((item) => item.toJson()).toList(),
      },
    );
  }

  Future<void> saveAvailabilityWindows(List<AvailabilityWindow> windows) async {
    await GawaGoApi.put(
      '/accounts/me/availability/',
      body: {
        'availability_windows': windows.map((item) => item.toJson()).toList(),
      },
    );
  }

  Future<List<WorkerNotification>> getNotifications() async {
    final data = await GawaGoApi.getList('/notifications/');
    return data.map((item) => WorkerNotification.fromJson(item)).toList();
  }

  Future<void> markNotificationRead(int id) async {
    await GawaGoApi.patch('/notifications/$id/read/', body: {});
  }

  Future<void> deleteNotification(int id) async {
    await GawaGoApi.delete('/notifications/$id/');
  }

  Future<List<VerificationRequest>> getVerificationRequests() async {
    final data = await GawaGoApi.getList('/common/verification-requests/');
    return data.map((item) => VerificationRequest.fromJson(item)).toList();
  }

  Future<void> submitVerification({
    required String primaryPath,
    required String secondaryPath,
    String notes = '',
  }) async {
    await GawaGoApi.multipartPost(
      '/common/verification-requests/',
      fields: {
        'primary_id_name': primaryPath.split(RegExp(r'[/\\]')).last,
        'secondary_doc_name': secondaryPath.split(RegExp(r'[/\\]')).last,
        'notes': notes,
      },
      files: {
        'primary_id_file': primaryPath,
        'secondary_doc_file': secondaryPath,
      },
    );
  }
}
