/// Mirrors the report envelope from backend/apps/reports/services.py.
///
/// The backend returns the same shape for households, workers, and
/// administrators, so one model and one screen cover all three roles.
class ActivityReport {
  const ActivityReport({
    required this.scope,
    required this.title,
    required this.periodStart,
    required this.periodEnd,
    required this.summary,
    required this.sections,
  });

  final String scope;
  final String title;
  final String periodStart;
  final String periodEnd;

  /// Ordered metric label -> value. Values arrive as numbers, strings, or
  /// null (meaning "no data yet"), so they are kept dynamic and formatted
  /// at render time.
  final Map<String, dynamic> summary;
  final List<ReportSection> sections;

  factory ActivityReport.fromJson(Map<String, dynamic> json) {
    final period = _map(json['period']);
    return ActivityReport(
      scope: _text(json['scope']),
      title: _text(json['title'], 'Activity report'),
      periodStart: _text(period['start']),
      periodEnd: _text(period['end']),
      summary: _map(json['summary']),
      sections: _list(
        json['sections'],
      ).map((item) => ReportSection.fromJson(_map(item))).toList(),
    );
  }
}

class ReportSection {
  const ReportSection({
    required this.title,
    required this.description,
    required this.columns,
    required this.rows,
  });

  final String title;
  final String description;
  final List<String> columns;
  final List<List<String>> rows;

  factory ReportSection.fromJson(Map<String, dynamic> json) {
    return ReportSection(
      title: _text(json['title']),
      description: _text(json['description']),
      columns: _list(json['columns']).map((item) => item.toString()).toList(),
      rows: _list(json['rows'])
          .map(
            (row) => _list(row).map((cell) => cell?.toString() ?? '').toList(),
          )
          .toList(),
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const {};

List<dynamic> _list(dynamic value) => value is List<dynamic> ? value : const [];

String _text(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;
