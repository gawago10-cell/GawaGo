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

  /// Open jobs ranked for this worker by the content-based AI recommender,
  /// each carrying the skill-vs-proximity explainability breakdown.
  Future<List<RecommendedJob>> getRecommendedJobs() async {
    final data = await GawaGoApi.getList('/matching/recommended-jobs/');
    return data.map((item) => RecommendedJob.fromJson(item)).toList();
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

  /// The four optional metrics mirror the web review form; each is 1-5 and
  /// the backend averages whichever are supplied into the overall rating.
  Future<void> reviewHousehold(
    WorkerJob job, {
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
        'target_username': job.householdUsername,
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

  // ---- Portfolio: rated skills, certificates and before/after samples ----
  // All of these hang off /accounts/me/portfolio/, which the web profile
  // page already drives; mobile reads and writes the same records.

  Future<WorkerPortfolio> getPortfolio() async {
    return WorkerPortfolio.fromJson(
      await GawaGoApi.get('/accounts/me/portfolio/'),
    );
  }

  Future<void> addPortfolioSkill({
    required String skillName,
    required String proficiency,
  }) async {
    await GawaGoApi.post(
      '/accounts/me/portfolio/skills/',
      body: {'skill_name': skillName, 'proficiency': proficiency},
    );
  }

  Future<void> deletePortfolioSkill(int skillId) async {
    await GawaGoApi.delete('/accounts/me/portfolio/skills/$skillId/');
  }

  Future<void> addCertification({
    required String certificateName,
    required String certificateType,
    String issuer = '',
    String issueDate = '',
    String expiryDate = '',
    String? filePath,
  }) async {
    final fields = {
      'certificate_name': certificateName,
      'certificate_type': certificateType,
      'issuer': issuer,
      if (issueDate.isNotEmpty) 'issue_date': issueDate,
      if (expiryDate.isNotEmpty) 'expiry_date': expiryDate,
    };
    if (filePath == null) {
      await GawaGoApi.post(
        '/accounts/me/portfolio/certifications/',
        body: fields,
      );
      return;
    }
    await GawaGoApi.multipartPost(
      '/accounts/me/portfolio/certifications/',
      fields: fields,
      files: {'certificate_file': filePath},
    );
  }

  Future<void> deleteCertification(int certificationId) async {
    await GawaGoApi.delete(
      '/accounts/me/portfolio/certifications/$certificationId/',
    );
  }

  /// `image` is required server-side and `before_image` is not, so the
  /// before photo is sent as both -- the same thing the web form does.
  Future<void> addWorkSample({
    required String title,
    required String description,
    required String beforePath,
    required String afterPath,
  }) async {
    await GawaGoApi.multipartPost(
      '/accounts/me/portfolio/items/',
      fields: {'title': title, 'description': description},
      files: {
        'image': beforePath,
        'before_image': beforePath,
        'after_image': afterPath,
      },
    );
  }

  /// Photos are optional on an edit: leaving both out renames the sample
  /// without re-uploading anything.
  Future<void> updateWorkSample(
    int itemId, {
    required String title,
    required String description,
    String? beforePath,
    String? afterPath,
  }) async {
    final fields = {'title': title, 'description': description};
    final files = <String, String>{
      if (beforePath != null) ...{
        'image': beforePath,
        'before_image': beforePath,
      },
      'after_image': ?afterPath,
    };
    if (files.isEmpty) {
      await GawaGoApi.patch(
        '/accounts/me/portfolio/items/$itemId/',
        body: fields,
      );
      return;
    }
    await GawaGoApi.multipartPatch(
      '/accounts/me/portfolio/items/$itemId/',
      fields: fields,
      files: files,
    );
  }

  Future<void> deleteWorkSample(int itemId) async {
    await GawaGoApi.delete('/accounts/me/portfolio/items/$itemId/');
  }

  /// Every job this worker finished, newest first -- the "Employment
  /// History" section. Filtered by user id because that is what the jobs
  /// endpoint's `worker` parameter takes.
  Future<List<WorkerJob>> getEmploymentHistory(int workerUserId) async {
    final uri = Uri(
      path: '/jobs/',
      queryParameters: {'worker': '$workerUserId', 'status': 'completed'},
    );
    final data = await GawaGoApi.getList(uri.toString());
    return data.map((item) => WorkerJob.fromJson(item)).toList();
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
