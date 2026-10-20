import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// The AI match explainability bar (AGENTS.md I.C): how much of the score
/// came from skill fit versus proximity. Shared by the worker's "Find Jobs
/// for Me" cards and the household's recommended-worker cards so both read
/// the same, matching the web's `.worker-ai-match-breakdown`.
class AiMatchBreakdown extends StatelessWidget {
  const AiMatchBreakdown({
    super.key,
    required this.skillSharePercent,
    required this.exactSkillMatch,
  });

  /// Skill fit's share of the score, 0-100; null hides the breakdown.
  final int? skillSharePercent;
  final bool exactSkillMatch;

  static const proximityColor = Color(0xFFF0C040);

  @override
  Widget build(BuildContext context) {
    final skillShare = skillSharePercent;
    if (skillShare == null) return const SizedBox.shrink();
    final proximityShare = 100 - skillShare;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: skillShare,
                    child: Container(color: GawaGoColors.primary),
                  ),
                  Expanded(
                    flex: proximityShare,
                    child: Container(color: proximityColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Why this match: $skillShare% skill fit, $proximityShare% proximity'
            '${exactSkillMatch ? ' — exact skill match' : ''}',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
