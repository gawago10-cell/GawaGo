import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../utils/display_formatters.dart';

/// A job's start and end, each with the day of the week, and its working
/// days -- the mobile twin of the web's JobScheduleBox.jsx, with the same
/// words: Starts / Started, Ends / Ended. A one-day job with no end date
/// ends the day it starts.
class JobScheduleBox extends StatelessWidget {
  const JobScheduleBox({
    super.key,
    required this.startDate,
    required this.endDate,
    this.workingDays,
    this.finished = false,
    this.today,
  });

  final String? startDate;
  final String? endDate;
  final int? workingDays;
  final bool finished;

  /// For tests; defaults to now.
  final DateTime? today;

  static String _iso(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final start = (startDate ?? '').trim();
    final given = (endDate ?? '').trim();
    if (start.isEmpty && given.isEmpty) return const SizedBox.shrink();
    final days = (workingDays ?? 0) > 0 ? workingDays : null;
    final end = given.isNotEmpty ? given : (days == 1 ? start : '');
    final now = _iso(today ?? DateTime.now());
    final startWord = start.isEmpty
        ? 'Start'
        : start.compareTo(now) > 0
        ? 'Starts'
        : 'Started';
    final endWord = end.isEmpty
        ? 'End'
        : finished || end.compareTo(now) < 0
        ? 'Ended'
        : 'Ends';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GawaGoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Cell(label: startWord, date: start)),
                Container(width: 1, color: GawaGoColors.border),
                Expanded(child: _Cell(label: endWord, date: end)),
              ],
            ),
          ),
          if (days != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: GawaGoColors.leafTint,
                border: Border(top: BorderSide(color: GawaGoColors.border)),
              ),
              child: Text(
                '$days working day${days == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: GawaGoColors.leafDeep,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatJobDay(date),
            style: TextStyle(
              color: date.isEmpty ? GawaGoColors.textMuted : GawaGoColors.ink,
              fontSize: 13.5,
              fontWeight: date.isEmpty ? FontWeight.w600 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
