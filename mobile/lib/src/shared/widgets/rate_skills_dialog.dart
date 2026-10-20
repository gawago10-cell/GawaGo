import 'package:flutter/material.dart';

import '../../core/errors/api_error.dart';
import '../../core/theme/gawago_colors.dart';

/// One skill a household can rate after a completed job.
class RatableSkill {
  const RatableSkill({required this.id, required this.name});

  final int id;
  final String name;
}

/// Receives only the skills the household actually rated, as skill id to
/// 1-5. Unrated skills are left out rather than sent as a default score, so a
/// skipped skill never moves the worker's average.
typedef RateSkillsSubmit = Future<void> Function(Map<int, int> ratings);

/// "Rate their skills" -- the per-skill ratings the web offers after a
/// review. Optional by design: closing the dialog or submitting nothing is
/// fine, and the review itself has already been saved.
///
/// Returns true if at least one skill rating was submitted.
Future<bool> showRateSkillsDialog({
  required BuildContext context,
  required String workerName,
  required List<RatableSkill> skills,
  required RateSkillsSubmit onSubmit,
}) async {
  if (skills.isEmpty) return false;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _RateSkillsDialog(
      workerName: workerName,
      skills: skills,
      onSubmit: onSubmit,
    ),
  );
  return result ?? false;
}

class _RateSkillsDialog extends StatefulWidget {
  const _RateSkillsDialog({
    required this.workerName,
    required this.skills,
    required this.onSubmit,
  });

  final String workerName;
  final List<RatableSkill> skills;
  final RateSkillsSubmit onSubmit;

  @override
  State<_RateSkillsDialog> createState() => _RateSkillsDialogState();
}

class _RateSkillsDialogState extends State<_RateSkillsDialog> {
  final Map<int, int> _ratings = {};
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting || _ratings.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(Map<int, int>.of(_ratings));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException && error.message.isNotEmpty
              ? error.message
              : 'Unable to save these ratings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GawaGoColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RATE THEIR SKILLS',
                style: TextStyle(
                  color: GawaGoColors.leafDeep,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How good was ${widget.workerName.isEmpty ? 'the worker' : widget.workerName} at each skill? '
                'Rate only the ones that apply.',
                style: const TextStyle(
                  color: GawaGoColors.textMuted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              for (final skill in widget.skills)
                _SkillRow(
                  skill: skill,
                  value: _ratings[skill.id] ?? 0,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          // Tapping the current score clears it again.
                          if (_ratings[skill.id] == value) {
                            _ratings.remove(skill.id);
                          } else {
                            _ratings[skill.id] = value;
                          }
                        }),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: GawaGoColors.danger,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting || _ratings.isEmpty
                          ? null
                          : _submit,
                      child: Text(_submitting ? 'Saving...' : 'Save ratings'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.skill,
    required this.value,
    required this.onChanged,
  });

  final RatableSkill skill;
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            skill.name,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          Row(
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  key: ValueKey('skill-${skill.id}-star-$star'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  tooltip: '$star of 5',
                  onPressed: onChanged == null ? null : () => onChanged!(star),
                  icon: Icon(
                    star <= value
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: star <= value
                        ? GawaGoColors.primary
                        : GawaGoColors.textFaint,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
