import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../utils/display_formatters.dart';

/// A job's schedule in words, shared by the box (My Jobs, dashboard) and the
/// compact lines (My Applications), like the web's describeJobSchedule.
class JobScheduleWords {
  const JobScheduleWords._({
    required this.start,
    required this.end,
    required this.startWord,
    required this.endWord,
    required this.workingDays,
  });

  final String start;
  final String end;
  final String startWord;
  final String endWord;
  final int? workingDays;

  String get daysText => workingDays == null
      ? ''
      : '$workingDays working day${workingDays == 1 ? '' : 's'}';

  static String _iso(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Null when the job has no dates.
  static JobScheduleWords? of({
    required String? startDate,
    required String? endDate,
    int? workingDays,
    bool finished = false,
    DateTime? today,
  }) {
    final start = (startDate ?? '').trim();
    final given = (endDate ?? '').trim();
    if (start.isEmpty && given.isEmpty) return null;
    final days = (workingDays ?? 0) > 0 ? workingDays : null;
    final end = given.isNotEmpty ? given : (days == 1 ? start : '');
    final now = _iso(today ?? DateTime.now());
    return JobScheduleWords._(
      start: start,
      end: end,
      startWord: start.isEmpty
          ? 'Start'
          : start.compareTo(now) > 0
          ? 'Starts'
          : 'Started',
      endWord: end.isEmpty
          ? 'End'
          : finished || end.compareTo(now) < 0
          ? 'Ended'
          : 'Ends',
      workingDays: days,
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final schedule = JobScheduleWords.of(
      startDate: startDate,
      endDate: endDate,
      workingDays: workingDays,
      finished: finished,
      today: today,
    );
    if (schedule == null) return const SizedBox.shrink();
    final start = schedule.start;
    final end = schedule.end;
    final startWord = schedule.startWord;
    final endWord = schedule.endWord;
    final days = schedule.workingDays;

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
                Expanded(
                  child: _Cell(label: startWord, date: start),
                ),
                Container(width: 1, color: GawaGoColors.border),
                Expanded(
                  child: _Cell(label: endWord, date: end),
                ),
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
                schedule.daysText,
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

/// The same schedule as short lines for a list row (My Applications), with
/// the schedule type ("One-Time") beside the working days -- the twin of the
/// web's JobScheduleLines. Without dates it shows the schedule wording alone.
class JobScheduleLines extends StatelessWidget {
  const JobScheduleLines({
    super.key,
    required this.startDate,
    required this.endDate,
    this.workingDays,
    this.finished = false,
    this.scheduleLabel = '',
    this.today,
  });

  final String? startDate;
  final String? endDate;
  final int? workingDays;
  final bool finished;
  final String scheduleLabel;

  /// For tests; defaults to now.
  final DateTime? today;

  static const _valueStyle = TextStyle(
    color: GawaGoColors.ink,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final schedule = JobScheduleWords.of(
      startDate: startDate,
      endDate: endDate,
      workingDays: workingDays,
      finished: finished,
      today: today,
    );
    if (schedule == null) {
      return Text(
        scheduleLabel.isEmpty ? 'Not set' : scheduleLabel,
        style: _valueStyle,
      );
    }
    final extra = [
      scheduleLabel,
      schedule.daysText,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(schedule.startWord, schedule.start),
        const SizedBox(height: 2),
        _line(schedule.endWord, schedule.end),
        if (extra.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            extra,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(String word, String date) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$word  ',
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: formatJobDay(date),
            style: date.isEmpty
                ? _valueStyle.copyWith(
                    color: GawaGoColors.textMuted,
                    fontWeight: FontWeight.w600,
                  )
                : _valueStyle,
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
