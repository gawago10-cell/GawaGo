import 'package:flutter/material.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/authenticated_image.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin review of worker credentials (TESDA certificates, licences, ...),
/// the mobile twin of the web "Worker Credentials" queue. Approving one is
/// what gives it the verified badge on the worker's portfolio (AGENTS.md
/// II.C). Government IDs are reviewed in the Verification Queue instead.
class AdminCredentialsQueue extends StatefulWidget {
  const AdminCredentialsQueue({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<AdminCredentialsQueue> createState() => _AdminCredentialsQueueState();
}

class _AdminCredentialsQueueState extends State<AdminCredentialsQueue> {
  static const _filters = {
    'pending': 'Pending',
    'approved': 'Approved',
    'rejected': 'Rejected',
    'all': 'All',
  };

  String _filter = 'pending';
  late Future<List<AdminCertificate>> _future = _load();
  int? _savingId;

  Future<List<AdminCertificate>> _load() =>
      widget.repository.getCertificates(status: _filter);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<String?> _askRejectReason() => showDialog<String>(
    context: context,
    builder: (_) => const _RejectReasonDialog(),
  );

  Future<void> _decide(AdminCertificate certificate, String status) async {
    if (_savingId != null) return;
    var notes = '';
    if (status == 'rejected') {
      final reason = await _askRejectReason();
      // Cancel means "don't reject", not "reject with no reason".
      if (reason == null || !mounted) return;
      notes = reason;
    }
    setState(() => _savingId = certificate.id);
    try {
      await widget.repository.reviewCertificate(
        certificate.id,
        status: status,
        notes: notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Certificate approved.'
                : 'Certificate rejected.',
          ),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Worker Credentials',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Approve a certificate to give it the verified badge on the worker\'s portfolio.',
                style: TextStyle(color: GawaGoColors.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in _filters.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _filter == entry.key,
                      onSelected: (_) {
                        setState(() {
                          _filter = entry.key;
                          _future = _load();
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminCertificate>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(error: snapshot.error, onRetry: _reload);
              }
              if (!snapshot.hasData) return const AppLoadingState();
              final certificates = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: certificates.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const [
                          Text(
                            'No certificates match this filter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: GawaGoColors.textMuted),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        itemCount: certificates.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _CertificateCard(
                          certificate: certificates[index],
                          saving: _savingId == certificates[index].id,
                          onApprove: () =>
                              _decide(certificates[index], 'approved'),
                          onReject: () =>
                              _decide(certificates[index], 'rejected'),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.certificate,
    required this.saving,
    required this.onApprove,
    required this.onReject,
  });

  final AdminCertificate certificate;
  final bool saving;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (certificate.issuer.isNotEmpty) 'Issued by ${certificate.issuer}',
      if (certificate.issueDate.isNotEmpty) 'Issued ${certificate.issueDate}',
      if (certificate.expiryDate.isNotEmpty)
        'Expires ${certificate.expiryDate}',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (certificate.fileUrl.isNotEmpty && certificate.fileType == 'image')
            AuthenticatedImage(url: certificate.fileUrl, height: 170)
          else if (certificate.fileUrl.isNotEmpty)
            CertificateFileNote(isPdf: certificate.fileType == 'pdf'),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        certificate.name.isEmpty
                            ? 'Untitled certificate'
                            : certificate.name,
                        style: const TextStyle(
                          color: GawaGoColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      certificate.statusLabel,
                      style: TextStyle(
                        color: certificate.status == 'approved'
                            ? GawaGoColors.leafDeep
                            : certificate.status == 'rejected'
                            ? Colors.red.shade700
                            : GawaGoColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    certificate.workerName,
                    if (certificate.workerLocation.isNotEmpty)
                      certificate.workerLocation,
                  ].join(' · '),
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                if (certificate.typeLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    certificate.typeLabel,
                    style: const TextStyle(
                      color: GawaGoColors.text,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join(' · '),
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (certificate.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Note: ${certificate.notes}',
                    style: const TextStyle(
                      color: GawaGoColors.text,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving || certificate.status == 'rejected'
                            ? null
                            : onReject,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving || certificate.status == 'approved'
                            ? null
                            : onApprove,
                        child: Text(saving ? 'Saving…' : 'Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional rejection reason. Its own widget so the text
/// controller lives exactly as long as the dialog, including its closing
/// animation.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this certificate?'),
      content: TextField(
        controller: _reason,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason (shown to the worker, optional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
