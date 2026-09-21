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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8D0C3), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: GawaGoColors.primary,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                ?action,
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
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: GawaGoColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
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
    final color = muted ? const Color(0xFF6C7870) : GawaGoColors.primary;
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
        color: const Color(0xFFF7F5F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E0D6)),
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
