import 'dart:convert';

import '../../../core/api/gawago_api.dart';
import 'report_models.dart';

class ReportRepository {
  const ReportRepository();

  /// Platform-wide report. Requires a staff account.
  Future<ActivityReport> getPlatformReport({String? start, String? end}) async {
    return ActivityReport.fromJson(
      await GawaGoApi.get('/reports/platform/${_query(start, end)}'),
    );
  }

  /// The same report as CSV (AGENTS.md IV.B), straight from the backend's
  /// export so the columns match the web download exactly.
  Future<String> getPlatformReportCsv({String? start, String? end}) async {
    final query = _query(start, end);
    final separator = query.isEmpty ? '?' : '&';
    final bytes = await GawaGoApi.getBytes(
      '/reports/platform/$query${separator}export=csv',
    );
    return utf8.decode(bytes);
  }

  String _query(String? start, String? end) {
    final parts = <String>[
      if (start != null && start.isNotEmpty) 'start=$start',
      if (end != null && end.isNotEmpty) 'end=$end',
    ];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }
}
