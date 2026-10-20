import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// A white card with the green title bar the web profile pages use, and an
/// optional action button on the right of that bar.
///
/// Shared because both profile screens are built from it: the worker's own
/// editable profile and the read-only one a household sees on an applicant.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: GawaGoColors.line)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: GawaGoColors.fontHeading,
                      color: GawaGoColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                // Flexible so a wide action (e.g. a labelled button) shrinks
                // instead of forcing the row past 320dp (F-07).
                if (action != null) Flexible(child: action!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

class ProfileSectionButton extends StatelessWidget {
  const ProfileSectionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: GawaGoColors.leafDeep,
        side: const BorderSide(color: GawaGoColors.lineStrong, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: GawaGoColors.fontBody,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      child: Text(label),
    );
  }
}

/// The muted "nothing here yet" line inside a [ProfileSection].
class SectionEmptyText extends StatelessWidget {
  const SectionEmptyText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: GawaGoColors.textMuted,
        fontSize: 14.5,
        height: 1.4,
      ),
    );
  }
}

/// Small tinted pill used for proficiency, service type and rate labels.
class SoftGreenPill extends StatelessWidget {
  const SoftGreenPill({super.key, required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? GawaGoColors.textMuted : GawaGoColors.leafDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// The per-skill ratings a worker received on one completed job, shown on
/// both employment-history views. Entries are skill name -> rating (1-5).
class JobSkillRatingChips extends StatelessWidget {
  const JobSkillRatingChips({super.key, required this.ratings});

  final List<MapEntry<String, double>> ratings;

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final entry in ratings)
            SoftGreenPill(
              label: '${entry.key} ★ ${entry.value.toStringAsFixed(1)}',
            ),
        ],
      ),
    );
  }
}

/// One rated skill row: a green accent bar, the skill name, its proficiency
/// and — when households have rated it — the earned average.
class ProfileSkillTile extends StatelessWidget {
  const ProfileSkillTile({
    super.key,
    required this.skillName,
    required this.proficiencyLabel,
    required this.averageRating,
    required this.ratingCount,
    this.trailing,
  });

  final String skillName;
  final String proficiencyLabel;
  final double? averageRating;
  final int ratingCount;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: GawaGoColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skillName,
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (proficiencyLabel.isNotEmpty)
                      SoftGreenPill(label: proficiencyLabel),
                    if (averageRating != null)
                      Text(
                        '${averageRating!.toStringAsFixed(2)} from $ratingCount '
                        '${ratingCount == 1 ? 'rating' : 'ratings'}',
                        style: const TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
