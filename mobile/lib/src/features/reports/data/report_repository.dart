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

  String _query(String? start, String? end) {
    final parts = <String>[
      if (start != null && start.isNotEmpty) 'start=$start',
      if (end != null && end.isNotEmpty) 'end=$end',
    ];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }
}
