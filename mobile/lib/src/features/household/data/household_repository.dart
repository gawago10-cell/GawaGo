import '../../../core/api/gawago_api.dart';
import '../../../core/config/api_config.dart';
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
            fields: GawaGoApi.multipartFields(values),
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
            fields: GawaGoApi.multipartFields(values),
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

  /// Smart Matching's rule order is the default; `rank: 'ai'` opts into the
  /// content-based re-ranking instead. Kept as a parameter so neither
  /// ranking replaces the other.
  Future<List<RecommendedWorker>> getRecommendedWorkers(
    int jobId, {
    String? rank,
  }) async {
    final rankParam = rank == null ? '' : '&rank=$rank';
    final response = await GawaGoApi.get(
      '/matching/recommended-workers/?job_id=$jobId$rankParam',
      // Scores every candidate and resolves routes: a cold call takes around
      // ten seconds, well past the default timeout.
      timeout: ApiConfig.matchingTimeout,
    );
    final results = response['results'] is List
        ? response['results'] as List
        : const [];
    return results.map((item) => RecommendedWorker.fromJson(item)).toList();
  }

  /// The four detail scores are optional: null means "not rated" and is
  /// simply left out of the request rather than sent as a zero.
  Future<void> reviewWorker(
    HouseholdJob job,
    HouseholdApplication application, {
    required double rating,
    required String feedback,
    int? qualityOfWork,
    int? punctuality,
    int? communication,
    int? professionalism,
  }) async {
    await GawaGoApi.post(
      '/reviews/',
      body: {
        'target_username': application.workerUsername,
        'job_id': job.id,
        'job_title': job.title,
        'rating': rating,
        'feedback': feedback,
        'quality_of_work': ?qualityOfWork,
        'punctuality': ?punctuality,
        'communication': ?communication,
        'professionalism': ?professionalism,
      },
    );
  }

  /// Rates individual skills on a completed job. Sent one request per skill
  /// (that is the endpoint's shape), and stops at the first failure so the
  /// caller can tell the person rather than half-saving silently.
  /// Posts one rating per skill. Ids found in [unlistedSkillNames] are not
  /// real portfolio entries but skills the worker never listed (the job's own
  /// skill): those are sent by name and the backend files the rating under
  /// that worker, as the web client does.
  Future<void> rateSkills(
    HouseholdJob job,
    Map<int, int> ratingsBySkillId, {
    int? workerId,
    Map<int, String> unlistedSkillNames = const {},
  }) async {
    for (final entry in ratingsBySkillId.entries) {
      final unlistedName = unlistedSkillNames[entry.key];
      await GawaGoApi.post(
        '/accounts/jobs/${job.id}/skill-ratings/',
        body: unlistedName != null
            ? {
                'skill_name': unlistedName,
                'worker_id': workerId,
                'rating': entry.value,
              }
            : {'skill': entry.key, 'rating': entry.value},
      );
    }
  }

  /// Another worker's public portfolio -- the rated skills, certificates and
  /// work samples a household reads before hiring. Distinct from the worker's
  /// own `/accounts/me/portfolio/`, which only serves the signed-in user.
  Future<WorkerPortfolio> getWorkerPortfolio(int workerUserId) async {
    return WorkerPortfolio.fromJson(
      await GawaGoApi.get('/accounts/profiles/$workerUserId/portfolio/'),
    );
  }

  /// That worker's completed jobs, newest first.
  Future<List<WorkerJobHistoryEntry>> getWorkerJobHistory(
    int workerUserId,
  ) async {
    final uri = Uri(
      path: '/jobs/',
      queryParameters: {'worker': '$workerUserId', 'status': 'completed'},
    );
    final data = await GawaGoApi.getList(uri.toString());
    return data.map((item) => WorkerJobHistoryEntry.fromJson(item)).toList();
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

  /// The unread badge number only, so polling for it doesn't download every
  /// page of notifications.
  Future<int> getUnreadNotificationCount() async {
    final data = await GawaGoApi.get('/notifications/unread-count/');
    final value = data['unread'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
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
    required String primaryIdType,
    String primaryIdOtherName = '',
    String notes = '',
  }) async {
    await GawaGoApi.multipartPost(
      '/common/verification-requests/',
      fields: {
        'primary_id_type': primaryIdType,
        // The backend labels the request from the chosen type; it only reads
        // this when the type is "other".
        if (primaryIdType == 'other') 'primary_id_name': primaryIdOtherName,
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
