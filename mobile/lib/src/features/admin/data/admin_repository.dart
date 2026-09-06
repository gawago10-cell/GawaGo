import '../../../core/api/gawago_api.dart';
import 'admin_models.dart';

class AdminRepository {
  const AdminRepository();

  Future<AdminDashboardMetrics> getDashboardMetrics() async {
    return AdminDashboardMetrics.fromJson(
      await GawaGoApi.get('/analytics/dashboard-metrics/'),
    );
  }

  Future<List<AdminVerificationRequest>> getVerificationRequests() async {
    final data = await GawaGoApi.getList('/common/verification-requests/');
    return data
        .map((item) => AdminVerificationRequest.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> reviewVerification(
    int requestId, {
    required String action,
    String reviewNote = '',
  }) async {
    await GawaGoApi.post(
      '/common/verification-requests/$requestId/review/',
      body: {
        'action': action,
        if (reviewNote.trim().isNotEmpty) 'review_note': reviewNote.trim(),
      },
    );
  }
}
