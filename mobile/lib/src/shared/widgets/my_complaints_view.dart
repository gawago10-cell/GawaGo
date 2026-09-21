import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../../features/complaints/data/complaint_models.dart';
import '../../features/complaints/data/complaint_repository.dart';
import 'async_state.dart';

/// "My Reports" -- incidents the signed-in user filed, or was named in.
/// Distinct from the activity report: this tracks case status, not a
/// personal summary.
class MyComplaintsView extends StatefulWidget {
  const MyComplaintsView({
    super.key,
    this.repository = const ComplaintRepository(),
    this.currentUsername,
  });

  final ComplaintRepository repository;
  final String? currentUsername;

  @override
  State<MyComplaintsView> createState() => _MyComplaintsViewState();
}

class _MyComplaintsViewState extends State<MyComplaintsView> {
  late Future<List<ComplaintReport>> _future = widget.repository
      .getMyComplaints();

  void _reload() {
    setState(() => _future = widget.repository.getMyComplaints());
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFD8D0C3),
                    width: 1.2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Text(
                        'My Reports',
                        style: TextStyle(
                          color: GawaGoColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE6E0D6)),
                    const AppEmptyState(
                      icon: Icons.flag_outlined,
                      title: 'No reports yet',
                      message: 'Reports you file will appear here.',
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
              currentUsername: widget.currentUsername,
            ),
          ),
        );
      },
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.currentUsername,
  });

  final ComplaintReport complaint;
  final String? currentUsername;

  @override
  Widget build(BuildContext context) {
    final isFiledByMe = complaint.complainantUsername == currentUsername;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
                    Text(
                      isFiledByMe ? 'Filed by you' : 'Filed about you',
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
            '${complaint.jobTitle.isEmpty ? "Job report" : complaint.jobTitle} '
            '· ${complaint.createdAt.length >= 10 ? complaint.createdAt.substring(0, 10) : complaint.createdAt}',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 12),
          ),
          if (isFiledByMe) ...[
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
                color: const Color(0xFFE8F5E9),
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
    'resolved' => const Color(0xFF2D7A4F),
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
