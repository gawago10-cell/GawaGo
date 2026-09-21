import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// Optional 1-5 detail scores mirroring web's renderHouseholdReviewMetricInputs
/// (AppViews.jsx); the backend averages whichever are supplied into the
/// overall rating, so absent ones are simply left out of the submission.
const _metricFields = [
  ('quality_of_work', 'Quality of Work'),
  ('punctuality', 'Punctuality'),
  ('communication', 'Communication'),
  ('professionalism', 'Professionalism'),
];

typedef RateReviewSubmit =
    Future<void> Function({
      required double rating,
      required String feedback,
      int? qualityOfWork,
      int? punctuality,
      int? communication,
      int? professionalism,
    });

/// "Rate & Review" -- always tied to one hired worker on one job. Shown as a
/// modal, matching web's dashboard rating card, so the dashboard, My Jobs
/// history, and an applicant's detail page can all open the exact same UI
/// instead of three forked review forms.
///
/// Returns true if a rating was submitted.
Future<bool> showRateReviewDialog({
  required BuildContext context,
  required String workerName,
  required String workerInitial,
  required bool workerVerified,
  required RateReviewSubmit onSubmit,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _RateReviewDialog(
      workerName: workerName,
      workerInitial: workerInitial,
      workerVerified: workerVerified,
      onSubmit: onSubmit,
    ),
  );
  return result ?? false;
}

class _RateReviewDialog extends StatefulWidget {
  const _RateReviewDialog({
    required this.workerName,
    required this.workerInitial,
    required this.workerVerified,
    required this.onSubmit,
  });

  final String workerName;
  final String workerInitial;
  final bool workerVerified;
  final RateReviewSubmit onSubmit;

  @override
  State<_RateReviewDialog> createState() => _RateReviewDialogState();
}

class _RateReviewDialogState extends State<_RateReviewDialog> {
  double _rating = 5;
  final Map<String, int> _metrics = {};
  final _feedback = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        rating: _rating,
        feedback: _feedback.text.trim(),
        qualityOfWork: _metrics['quality_of_work'],
        punctuality: _metrics['punctuality'],
        communication: _metrics['communication'],
        professionalism: _metrics['professionalism'],
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Unable to submit this rating. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RateReviewHeader(
                name: widget.workerName,
                initial: widget.workerInitial,
                verified: widget.workerVerified,
                onClose: () => Navigator.of(context).pop(false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RATE & REVIEW',
                      style: TextStyle(
                        color: GawaGoColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'How was your experience?',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Overall Rating',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ...List.generate(5, (index) {
                          final value = index + 1.0;
                          return IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _rating = value),
                            icon: Icon(
                              _rating >= value
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: const Color(0xFFE0A82E),
                              size: 30,
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        Text(
                          '${_rating.toStringAsFixed(0)}/5',
                          style: const TextStyle(
                            color: GawaGoColors.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: GawaGoColors.border, height: 1),
                    const SizedBox(height: 14),
                    const Text(
                      'Specific metrics (optional)',
                      style: TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final field in _metricFields)
                      _MetricStarRow(
                        label: field.$2,
                        value: _metrics[field.$1],
                        busy: _submitting,
                        onChanged: (value) =>
                            setState(() => _metrics[field.$1] = value),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Feedback (optional)',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _feedback,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: GawaGoColors.input,
                        hintText:
                            "Share details about the worker's performance...",
                        hintStyle: const TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: GawaGoColors.border,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: GawaGoColors.deepGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _submitting ? 'Submitting...' : 'Submit Rating',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting
                                ? null
                                : () => Navigator.of(context).pop(false),
                            style: FilledButton.styleFrom(
                              backgroundColor: GawaGoColors.input,
                              foregroundColor: GawaGoColors.textMuted,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateReviewHeader extends StatelessWidget {
  const _RateReviewHeader({
    required this.name,
    required this.initial,
    required this.verified,
    required this.onClose,
  });

  final String name;
  final String initial;
  final bool verified;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: const BoxDecoration(
        color: GawaGoColors.deepGreen,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: GawaGoColors.primary,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
                if (verified) ...[
                  const SizedBox(height: 2),
                  const Text(
                    '✓ Verified',
                    style: TextStyle(
                      color: GawaGoColors.primaryLight,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _MetricStarRow extends StatelessWidget {
  const _MetricStarRow({
    required this.label,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...List.generate(5, (index) {
            final score = index + 1;
            return IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              padding: EdgeInsets.zero,
              tooltip: '$label: $score',
              onPressed: busy ? null : () => onChanged(score),
              icon: Icon(
                (value ?? 0) >= score
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: const Color(0xFFE0A82E),
                size: 18,
              ),
            );
          }),
        ],
      ),
    );
  }
}
