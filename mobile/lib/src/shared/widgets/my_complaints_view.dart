import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../utils/display_formatters.dart';
import '../../features/complaints/data/complaint_models.dart';
import '../../features/complaints/data/complaint_repository.dart';
import 'async_state.dart';

/// "My Complaints" -- issues the signed-in user has filed. Reports about the
/// user are never shown: a report stays confidential from the person it
/// names, and the API only returns reports the caller filed.
class MyComplaintsView extends StatefulWidget {
  const MyComplaintsView({
    super.key,
    this.repository = const ComplaintRepository(),
    this.currentUsername,
    this.emptyMessage = 'Complaints you file will appear here.',
    this.emptyActions = const [],
    this.onOpenJob,
  });

  final ComplaintRepository repository;
  final String? currentUsername;

  /// Where to go to file one, with buttons there: the empty page used to
  /// say nothing about how to file.
  final String emptyMessage;
  final List<(String, VoidCallback)> emptyActions;

  /// Opens the complaint's job (workers); null hides the link.
  final ValueChanged<int>? onOpenJob;

  @override
  State<MyComplaintsView> createState() => _MyComplaintsViewState();
}

class _MyComplaintsViewState extends State<MyComplaintsView> {
  late Future<List<ComplaintReport>> _future = widget.repository
      .getMyComplaints();

  void _reload() {
    setState(() {
      _future = widget.repository.getMyComplaints();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ComplaintReport>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final complaints = snapshot.data!;
        if (complaints.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: GawaGoColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GawaGoColors.border, width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Text(
                        'My Complaints',
                        style: TextStyle(
                          fontFamily: GawaGoColors.fontHeading,
                          color: GawaGoColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: GawaGoColors.border),
                    AppEmptyState(
                      icon: Icons.flag_outlined,
                      title: 'No complaints yet',
                      message: widget.emptyMessage,
                    ),
                    if (widget.emptyActions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final (label, onPressed)
                                in widget.emptyActions)
                              OutlinedButton(
                                onPressed: onPressed,
                                child: Text(label),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: complaints.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _ComplaintCard(
              complaint: complaints[index],
              onOpenJob: widget.onOpenJob,
            ),
          ),
        );
      },
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint, this.onOpenJob});

  final ComplaintReport complaint;
  final ValueChanged<int>? onOpenJob;

  /// "2026-11-12T09:15:00+08:00" is already in Philippine time, so the date
  /// part is the local day.
  static String _day(String value) =>
      formatJobDate(value.length >= 10 ? value.substring(0, 10) : value);

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (complaint.respondentName.isNotEmpty ||
                        complaint.respondentUsername.isNotEmpty)
                      Text(
                        'About ${complaint.respondentName.isNotEmpty ? complaint.respondentName : complaint.respondentUsername}',
                        style: const TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusBadge(status: complaint.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${complaint.jobTitle.isEmpty ? "Job complaint" : complaint.jobTitle} '
            '· Filed ${_day(complaint.createdAt)}'
            // When the admin team moved it on, if on a later day.
            '${complaint.status != 'submitted' && complaint.updatedAt.isNotEmpty && _day(complaint.updatedAt) != _day(complaint.createdAt) ? ' · Updated ${_day(complaint.updatedAt)}' : ''}',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 12),
          ),
          if (onOpenJob != null && complaint.jobId != null)
            TextButton(
              onPressed: () => onOpenJob!(complaint.jobId!),
              style: TextButton.styleFrom(
                foregroundColor: GawaGoColors.leafDeep,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'View job',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          if (complaint.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              complaint.description,
              style: const TextStyle(color: GawaGoColors.text, fontSize: 13),
            ),
          ],
          if (complaint.resolution.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GawaGoColors.leafTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Resolution: ${complaint.resolution}',
                style: const TextStyle(fontSize: 12, color: GawaGoColors.text),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  Color get _color => switch (status) {
    'resolved' => GawaGoColors.leafDeep,
    'under_review' => const Color(0xFF1F6FB2),
    'closed' => Colors.grey,
    _ => const Color(0xFFB8860B),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        complaintStatusLabels[status] ?? status,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
