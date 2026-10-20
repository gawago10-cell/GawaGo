import 'dart:typed_data';
import '../../../core/api/gawago_api.dart';
import 'admin_models.dart';

class AdminRepository {
  const AdminRepository();

  /// Verification documents sit behind IsAuthenticated, so they are fetched
  /// as bytes with the bearer token attached rather than by URL.
  Future<Uint8List> getVerificationDocumentBytes(String path) {
    return GawaGoApi.getBytes(path);
  }

  Future<AdminDashboardMetrics> getDashboardMetrics() async {
    return AdminDashboardMetrics.fromJson(
      await GawaGoApi.get('/analytics/dashboard-metrics/'),
    );
  }

  Future<List<AdminVerificationRequest>> getVerificationRequests() async {
    final data = await GawaGoApi.getList('/common/verification-requests/');
    return data
        .map(
          (item) =>
              AdminVerificationRequest.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Worker credentials (TESDA certificates, licences...) for review.
  /// [status] is "pending", "approved", "rejected" or "all".
  Future<List<AdminCertificate>> getCertificates({
    String status = 'all',
  }) async {
    final data = await GawaGoApi.getList(
      '/accounts/admin/certificates/?status=${Uri.encodeQueryComponent(status)}',
    );
    return data
        .whereType<Map<String, dynamic>>()
        .map(AdminCertificate.fromJson)
        .toList();
  }

  Future<AdminCertificate> reviewCertificate(
    int certificateId, {
    required String status,
    String notes = '',
  }) async {
    return AdminCertificate.fromJson(
      await GawaGoApi.patch(
        '/accounts/admin/certificates/$certificateId/',
        body: {
          'verification_status': status,
          'verification_notes': notes.trim(),
        },
      ),
    );
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
