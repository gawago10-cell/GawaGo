import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// The AI match explainability bar (AGENTS.md I.C). The bar is the match
/// score itself, split into the points skill fit and distance earned; the
/// words give the real skill fit and distance. The old "70% skill fit, 30%
/// proximity" was each part's share of the score, which read as a 70% skill
/// fit on an exact match. Shared by the worker's "Find Jobs for Me" cards and
/// the household's recommended-worker cards so both read the same, matching
/// the web's `.worker-ai-match-breakdown`.
class AiMatchBreakdown extends StatelessWidget {
  const AiMatchBreakdown({
    super.key,
    required this.skillContribution,
    required this.proximityContribution,
    required this.skillSimilarity,
    required this.distanceKm,
    required this.exactSkillMatch,
  });

  /// The two weighted terms that sum to the AI score, each in [0, 1]. Both
  /// zero hides the breakdown.
  final double skillContribution;
  final double proximityContribution;

  /// The skill fit itself, in [0, 1].
  final double skillSimilarity;
  final double? distanceKm;
  final bool exactSkillMatch;

  static const proximityColor = Color(0xFFF0C040);

  @override
  Widget build(BuildContext context) {
    if (skillContribution + proximityContribution <= 0) {
      return const SizedBox.shrink();
    }
    // Rounded so the two always add up to the "N% match" shown with them.
    final matchPoints = ((skillContribution + proximityContribution) * 100)
        .round();
    final skillPoints = (skillContribution * 100).round().clamp(0, matchPoints);
    final distancePoints = matchPoints - skillPoints;
    final skillFit = (skillSimilarity * 100).round();
    final km = distanceKm;
    final distanceText = km == null
        ? ''
        : km < 0.1
        ? ', under 0.1 km away'
        : ', ${km.toStringAsFixed(1)} km away';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label:
                '$matchPoints% match: $skillPoints points from skill fit, '
                '$distancePoints from distance',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 6,
                color: GawaGoColors.surfaceMuted,
                child: Row(
                  children: [
                    if (skillPoints > 0)
                      Expanded(
                        flex: skillPoints,
                        child: Container(color: GawaGoColors.primary),
                      ),
                    if (distancePoints > 0)
                      Expanded(
                        flex: distancePoints,
                        child: Container(color: proximityColor),
                      ),
                    if (matchPoints < 100)
                      Expanded(
                        flex: 100 - matchPoints,
                        child: const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Why this match: $skillFit% skill fit'
            '${exactSkillMatch ? ' (exact skill match)' : ''}$distanceText',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
