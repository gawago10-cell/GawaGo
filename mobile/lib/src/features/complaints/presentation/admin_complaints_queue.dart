import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/widgets/async_state.dart';
import '../data/complaint_models.dart';
import '../data/complaint_repository.dart';

const _statusOptions = ['submitted', 'under_review', 'resolved', 'closed'];

/// Admin's incident-report queue. Distinct from the household/worker
/// activity report: a work queue to review and resolve, not a summary --
/// gated to superadmins only, matching the backend's IsPlatformSuperAdmin
/// requirement on these endpoints.
class AdminComplaintsQueue extends StatefulWidget {
  const AdminComplaintsQueue({
    super.key,
    this.repository = const ComplaintRepository(),
  });

  final ComplaintRepository repository;

  @override
  State<AdminComplaintsQueue> createState() => _AdminComplaintsQueueState();
}

class _AdminComplaintsQueueState extends State<AdminComplaintsQueue> {
  String? _statusFilter;
  late Future<List<ComplaintReport>> _future = _load();

  Future<List<ComplaintReport>> _load() =>
      widget.repository.getAdminComplaints(status: _statusFilter);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openReviewSheet(ComplaintReport complaint) async {
    final updated = await showModalBottomSheet<ComplaintReport>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _ReviewSheet(complaint: complaint, repository: widget.repository),
    );
    if (updated != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _statusFilter == null,
                  onTap: () {
                    setState(() => _statusFilter = null);
                    _reload();
                  },
                ),
                for (final status in _statusOptions)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FilterChip(
                      label: complaintStatusLabels[status] ?? status,
                      selected: _statusFilter == status,
                      onTap: () {
                        setState(() => _statusFilter = status);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ComplaintReport>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(error: snapshot.error, onRetry: _reload);
              }
              if (!snapshot.hasData) return const AppLoadingState();
              final complaints = snapshot.data!;
              if (complaints.isEmpty) {
                return const AppEmptyState(
                  message: 'No reports match this filter.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: complaints.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final complaint = complaints[index];
                    return _QueueRow(
                      complaint: complaint,
                      onTap: () => _openReviewSheet(complaint),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.complaint, required this.onTap});

  final ComplaintReport complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD8D0C3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaintTypeLabels[complaint.complaintType] ??
                        complaint.complaintType,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${complaint.complainantDetail?.displayName ?? complaint.complainantUsername} → '
                    '${complaint.respondentDetail?.displayName ?? (complaint.respondentUsername.isEmpty ? "—" : complaint.respondentUsername)}',
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (complaint.adminJobLabel.isNotEmpty)
                    Text(
                      complaint.adminJobLabel,
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              complaintStatusLabels[complaint.status] ?? complaint.status,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartyDetailCard extends StatelessWidget {
  const _PartyDetailCard({required this.kicker, required this.detail});

  final String kicker;
  final ComplaintPartyDetail detail;

  @override
  Widget build(BuildContext context) {
    final rating = detail.averageRating;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$kicker · ${detail.displayName}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: GawaGoColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rating != null
                ? '★ ${rating.toStringAsFixed(1)} (${detail.ratingCount} jobs)'
                : 'No rating yet',
            style: const TextStyle(fontSize: 11, color: GawaGoColors.textMuted),
          ),
          Text(
            [
              if (detail.locationLabel.isNotEmpty) detail.locationLabel,
              if (detail.memberSince.isNotEmpty)
                'Member since ${detail.memberSince}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: GawaGoColors.textMuted),
          ),
          Text(
            [
              if (detail.phone.isNotEmpty) detail.phone,
              if (detail.email.isNotEmpty) detail.email,
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: GawaGoColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.complaint, required this.repository});

  final ComplaintReport complaint;
  final ComplaintRepository repository;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late String _status = widget.complaint.status;
  late final _resolution = TextEditingController(
    text: widget.complaint.resolution,
  );
  // Blocking updates the report in place, so the sheet renders from this
  // rather than the immutable widget.complaint it was opened with.
  late ComplaintReport _current = widget.complaint;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _resolution.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_current.respondentUsername.isEmpty) return;
    await _applyBlock(blocked: false);
  }

  /// [durationDays] of 3 or 7 is a timed suspension that lifts itself;
  /// null is a permanent block.
  Future<void> _suspend(int? durationDays) async {
    final complaint = _current;
    if (complaint.respondentUsername.isEmpty) return;

    final durationLabel = durationDays == null
        ? 'permanently'
        : 'for $durationDays days';
    String reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(
            'Suspend ${complaint.respondentUsername} $durationLabel?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                durationDays == null
                    ? 'They will be signed out immediately and cannot log '
                          'back in until restored.'
                    : 'They will be signed out immediately and cannot log '
                          'back in for $durationDays days.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Reason (shown to the user)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                reason = controller.text.trim();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await _applyBlock(
      blocked: true,
      reason: reason,
      durationDays: durationDays,
    );
  }

  Future<void> _applyBlock({
    required bool blocked,
    String reason = '',
    int? durationDays,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.setRespondentBlocked(
        _current.id,
        blocked: blocked,
        reason: reason,
        durationDays: durationDays,
      );
      if (mounted) setState(() => _current = updated);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save({bool markResolved = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.updateAdmin(
        widget.complaint.id,
        status: markResolved ? 'resolved' : _status,
        resolution: _resolution.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Review Report #${widget.complaint.id}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: GawaGoColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.complaint.complainantDetail?.displayName ?? widget.complaint.complainantUsername} reported '
              '${widget.complaint.respondentDetail?.displayName ?? (widget.complaint.respondentUsername.isEmpty ? "an unspecified user" : widget.complaint.respondentUsername)}'
              '${widget.complaint.adminJobLabel.isEmpty ? "" : " on ${widget.complaint.adminJobLabel}"}',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.complaint.complainantDetail != null) ...[
              _PartyDetailCard(
                kicker: 'Reporter',
                detail: widget.complaint.complainantDetail!,
              ),
              const SizedBox(height: 8),
            ],
            if (widget.complaint.respondentDetail != null) ...[
              _PartyDetailCard(
                kicker: 'Reported',
                detail: widget.complaint.respondentDetail!,
              ),
              const SizedBox(height: 12),
            ],
            Text(widget.complaint.description),
            const SizedBox(height: 16),
            const Text(
              'Photo evidence',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (_current.evidenceUrls.isEmpty)
              const Text(
                'No photos were attached to this report.',
                style: TextStyle(color: GawaGoColors.textMuted, fontSize: 12),
              )
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _current.evidenceUrls.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _EvidenceThumb(
                      loader: () => widget.repository.getEvidenceBytes(
                        _current.evidenceUrls[index],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Account action',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: _current.respondentIsBlocked
                  ? [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _restore,
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: Text('Restore ${_current.respondentUsername}'),
                      ),
                      Chip(
                        label: Text(_current.suspensionLabel),
                        backgroundColor: const Color(0xFFFFE0E0),
                      ),
                    ]
                  : [
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _current.respondentUsername.isEmpty
                            ? null
                            : () => _suspend(3),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Suspend 3 Days'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _current.respondentUsername.isEmpty
                            ? null
                            : () => _suspend(7),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Suspend 7 Days'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _current.respondentUsername.isEmpty
                            ? null
                            : () => _suspend(null),
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Block Permanently'),
                      ),
                    ],
            ),
            const SizedBox(height: 16),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final status in _statusOptions)
                  ChoiceChip(
                    label: Text(complaintStatusLabels[status] ?? status),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _resolution,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Resolution notes',
                hintText: 'What action was taken?',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(markResolved: true),
                    child: const Text('Mark Resolved'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One evidence photo, fetched with the bearer token (the route is
/// permission-checked, so Image.network can't load it) and shown from memory.
class _EvidenceThumb extends StatefulWidget {
  const _EvidenceThumb({required this.loader});

  final Future<Uint8List> Function() loader;

  @override
  State<_EvidenceThumb> createState() => _EvidenceThumbState();
}

class _EvidenceThumbState extends State<_EvidenceThumb> {
  late final Future<Uint8List> _bytes = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: InteractiveViewer(child: Image.memory(snapshot.data!)),
              ),
            ),
            child: Image.memory(
              snapshot.data!,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) =>
                  const _ThumbPlaceholder(icon: Icons.broken_image_outlined),
            ),
          );
        }
        return _ThumbPlaceholder(
          icon: snapshot.hasError ? Icons.broken_image_outlined : null,
        );
      },
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({this.icon});

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      color: Colors.black12,
      alignment: Alignment.center,
      child: icon == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
    );
  }
}
