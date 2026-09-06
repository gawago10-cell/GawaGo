import '../../../core/api/gawago_api.dart';
import '../../worker/data/worker_models.dart';
import 'household_models.dart';

class HouseholdRepository {
  const HouseholdRepository();

  Future<HouseholdProfile> getProfile() async {
    return HouseholdProfile.fromJson(await GawaGoApi.get('/accounts/me/'));
  }

  Future<HouseholdProfile> updateProfile(
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
    return HouseholdProfile.fromJson(response);
  }

  Future<List<HouseholdJob>> getMyJobs() async {
    final data = await GawaGoApi.getList('/jobs/?mine=true');
    return data.map((item) => HouseholdJob.fromJson(item)).toList();
  }

  Future<HouseholdJob> getJob(int id) async {
    return HouseholdJob.fromJson(await GawaGoApi.get('/jobs/$id/'));
  }

  Future<HouseholdJob> createJob(
    Map<String, dynamic> values, {
    List<String> imagePaths = const [],
  }) async {
    final response = imagePaths.isEmpty
        ? await GawaGoApi.post('/jobs/', body: values)
        : await GawaGoApi.multipartPostMany(
            '/jobs/',
            fields: values.map(
              (key, value) => MapEntry(key, value?.toString() ?? ''),
            ),
            fileField: 'images',
            filePaths: imagePaths,
          );
    return HouseholdJob.fromJson(response);
  }

  Future<void> setApplicationStatus(int applicationId, String status) async {
    await GawaGoApi.patch(
      '/jobs/applications/$applicationId/status/',
      body: {'status': status},
    );
  }

  Future<void> sendHireRequest(int jobId, int workerId) async {
    await GawaGoApi.post(
      '/jobs/$jobId/hire-request/',
      body: {'worker_id': workerId},
    );
  }

  Future<void> updateJobStatus(int jobId, String status) async {
    await GawaGoApi.patch('/jobs/$jobId/', body: {'status': status});
  }

  Future<List<RecommendedWorker>> getRecommendedWorkers(int jobId) async {
    final response = await GawaGoApi.get(
      '/matching/recommended-workers/?job_id=$jobId',
    );
    final results = response['results'] is List
        ? response['results'] as List
        : const [];
    return results.map((item) => RecommendedWorker.fromJson(item)).toList();
  }

  Future<void> reviewWorker(
    HouseholdJob job,
    HouseholdApplication application, {
    required double rating,
    required String feedback,
  }) async {
    await GawaGoApi.post(
      '/reviews/',
      body: {
        'target_username': application.workerUsername,
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

  Future<List<GawaGoReview>> getWorkerReviews(String username) async {
    final data = await GawaGoApi.getList(
      '/reviews/?target_username=${Uri.encodeQueryComponent(username)}',
    );
    return data.map((item) => GawaGoReview.fromJson(item)).toList();
  }

  Future<List<GawaGoReview>> getGivenReviews() async {
    final profile = await getProfile();
    final data = await GawaGoApi.getList(
      '/reviews/?author_username=${Uri.encodeQueryComponent(profile.username)}',
    );
    return data.map((item) => GawaGoReview.fromJson(item)).toList();
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
