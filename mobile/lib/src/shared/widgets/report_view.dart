import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/api_error.dart';

import '../../core/theme/gawago_colors.dart';
import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/report_repository.dart';
import 'async_state.dart';
import 'responsive_metric_grid.dart';

/// Platform-wide activity report for administrators. The household/worker
/// activity summary was removed; only the admin-facing platform report
/// remains, reached from the Reports tab in AdminHomeScreen.
class ReportView extends StatefulWidget {
  const ReportView({super.key, this.repository = const ReportRepository()});

  final ReportRepository repository;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  DateTime? _start;
  DateTime? _end;
  late Future<ActivityReport> _future = _load();

  Future<ActivityReport> _load() {
    final start = _start == null ? null : _isoDate(_start!);
    final end = _end == null ? null : _isoDate(_end!);
    return widget.repository.getPlatformReport(start: start, end: end);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _start = selected;
      } else {
        _end = selected;
      }
      _future = _load();
    });
  }

  bool _exporting = false;

  /// The app has no file-save or share plugin, so the backend's CSV goes to
  /// the clipboard, ready to paste into a spreadsheet.
  Future<void> _copyCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await widget.repository.getPlatformReportCsv(
        start: _start == null ? null : _isoDate(_start!),
        end: _end == null ? null : _isoDate(_end!),
      );
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report copied as CSV. Paste it into a spreadsheet.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _clearPeriod() {
    setState(() {
      _start = null;
      _end = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ActivityReport>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) {
          return const AppLoadingState(message: 'Building your report...');
        }
        final report = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _ReportHeader(report: report),
              const SizedBox(height: 12),
              _PeriodFilter(
                start: _start,
                end: _end,
                onPickStart: () => _pickDate(isStart: true),
                onPickEnd: () => _pickDate(isStart: false),
                onClear: _start == null && _end == null ? null : _clearPeriod,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : _copyCsv,
                  icon: const Icon(Icons.table_view_outlined),
                  label: Text(_exporting ? 'Preparing CSV...' : 'Copy as CSV'),
                ),
              ),
              const SizedBox(height: 12),
              ResponsiveMetricGrid(
                children: report.summary.entries
                    .map(
                      (entry) => _SummaryCard(
                        label: _humanize(entry.key),
                        value: _formatValue(entry.key, entry.value),
                      ),
                    )
                    .toList(),
              ),
              for (final section in report.sections) ...[
                const SizedBox(height: 12),
                _SectionCard(section: section),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.report});

  final ActivityReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.title,
            style: const TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${report.periodStart} to ${report.periodEnd}',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClear,
  });

  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onPickStart,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(start == null ? 'From' : _isoDate(start!)),
        ),
        OutlinedButton.icon(
          onPressed: onPickEnd,
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(end == null ? 'To' : _isoDate(end!)),
        ),
        if (onClear != null)
          TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final ReportSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            section.description,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (section.rows.isEmpty)
            const Text(
              'No activity recorded in this period.',
              style: TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
            )
          else
            ...section.rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.isNotEmpty ? row.first : '',
                        style: const TextStyle(
                          color: GawaGoColors.text,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      row.length > 1 ? row[1] : '',
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

/// jobsPosted -> Jobs posted
String _humanize(String key) {
  final buffer = StringBuffer();
  for (final rune in key.runes) {
    final char = String.fromCharCode(rune);
    if (char.toUpperCase() == char && char.toLowerCase() != char) {
      buffer.write(' ${char.toLowerCase()}');
    } else {
      buffer.write(char);
    }
  }
  final spaced = buffer.toString().trim();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

String _formatValue(String key, dynamic value) {
  if (value == null || value.toString().isEmpty) return 'No data yet';
  final lowerKey = key.toLowerCase();
  if (lowerKey.endsWith('rate') || lowerKey.contains('percent')) {
    return '$value%';
  }
  // Money: agreed rates of completed jobs (GawaGo processes no payments).
  if (lowerKey.contains('spend') ||
      lowerKey.contains('earnings') ||
      lowerKey.endsWith('value')) {
    final amount = double.tryParse(value.toString());
    return amount == null ? 'PHP $value' : 'PHP ${amount.toStringAsFixed(2)}';
  }
  return value.toString();
}
