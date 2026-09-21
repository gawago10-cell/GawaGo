import '../../../core/api/gawago_api.dart';
import 'complaint_models.dart';

class ComplaintRepository {
  const ComplaintRepository();

  /// Reports the caller filed, plus reports naming them as respondent.
  Future<List<ComplaintReport>> getMyComplaints() async {
    final data = await GawaGoApi.getList('/complaints/');
    return data.map((item) => ComplaintReport.fromJson(item)).toList();
  }

  /// [respondentId] is required when the caller is a household (they pick
  /// which of the job's applicants the report is about); a worker's report
  /// always targets that job's household, derived server-side.
  Future<ComplaintReport> create({
    required int jobId,
    int? respondentId,
    required String complaintType,
    required String description,
    List<String> evidencePaths = const [],
  }) async {
    // Photos force multipart; without them keep the plain JSON body.
    if (evidencePaths.isNotEmpty) {
      final response = await GawaGoApi.multipartPostMany(
        '/complaints/create/',
        fields: {
          'job': '$jobId',
          if (respondentId != null) 'respondent': '$respondentId',
          'complaint_type': complaintType,
          'description': description,
        },
        fileField: 'evidence',
        filePaths: evidencePaths,
      );
      return ComplaintReport.fromJson(response);
    }

    final response = await GawaGoApi.post(
      '/complaints/create/',
      body: {
        'job': jobId,
        if (respondentId != null) 'respondent': respondentId,
        'complaint_type': complaintType,
        'description': description,
      },
    );
    return ComplaintReport.fromJson(response);
  }

  /// Suspend or restore the account a report was filed against (admin only).
  /// [durationDays] of 3 or 7 makes it a timed suspension that lifts itself;
  /// null means a permanent block.
  Future<ComplaintReport> setRespondentBlocked(
    int complaintId, {
    required bool blocked,
    String reason = '',
    int? durationDays,
  }) async {
    final response = await GawaGoApi.post(
      '/complaints/admin/$complaintId/block/',
      body: {
        'blocked': blocked,
        'reason': reason,
        'duration_days': durationDays,
      },
    );
    return ComplaintReport.fromJson(response);
  }

  Future<List<ComplaintReport>> getAdminComplaints({
    String? status,
    String? type,
  }) async {
    final params = <String>[
      if (status != null && status.isNotEmpty) 'status=$status',
      if (type != null && type.isNotEmpty) 'type=$type',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await GawaGoApi.getList('/complaints/admin/$query');
    return data.map((item) => ComplaintReport.fromJson(item)).toList();
  }

  Future<ComplaintReport> updateAdmin(
    int id, {
    String? status,
    String? resolution,
    String? adminNotes,
  }) async {
    final response = await GawaGoApi.patch(
      '/complaints/admin/$id/',
      body: {
        if (status != null) 'status': status,
        if (resolution != null) 'resolution': resolution,
        if (adminNotes != null) 'admin_notes': adminNotes,
      },
    );
    return ComplaintReport.fromJson(response);
  }
}
