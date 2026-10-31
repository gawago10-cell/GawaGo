import 'package:flutter/material.dart';

import '../../../core/api/gawago_api.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/utils/display_formatters.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/report_view.dart';
import '../../../shared/widgets/responsive_metric_grid.dart';
import '../../../shared/widgets/status_card.dart';
import '../../complaints/data/complaint_repository.dart';
import '../../complaints/presentation/admin_complaints_queue.dart';
import '../../reports/data/report_repository.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';
import 'admin_credentials_queue.dart';

enum _AdminPage { dashboard, verifications, credentials, complaints, reports }

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({
    super.key,
    required this.isSuperAdmin,
    required this.onLogout,
  });

  final bool isSuperAdmin;
  final VoidCallback onLogout;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _repository = const AdminRepository();
  _AdminPage _page = _AdminPage.dashboard;

  Future<void> _logout() async {
    await GawaGoApi.logout();
    await SessionStorage.clear();
    if (mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final mainDestinations = [
      GawaGoDrawerDestination(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        selected: _page == _AdminPage.dashboard,
        onTap: () => setState(() => _page = _AdminPage.dashboard),
      ),
      GawaGoDrawerDestination(
        icon: Icons.verified_user_outlined,
        label: 'Verification Queue',
        selected: _page == _AdminPage.verifications,
        onTap: () => setState(() => _page = _AdminPage.verifications),
      ),
      // Certificate review is open to every admin, like the ID queue.
      GawaGoDrawerDestination(
        icon: Icons.workspace_premium_outlined,
        label: 'Worker Credentials',
        selected: _page == _AdminPage.credentials,
        onTap: () => setState(() => _page = _AdminPage.credentials),
      ),
      // The complaint endpoints are superadmin-only, as on the web.
      if (widget.isSuperAdmin)
        GawaGoDrawerDestination(
          icon: Icons.flag_outlined,
          label: 'Complaints',
          selected: _page == _AdminPage.complaints,
          onTap: () => setState(() => _page = _AdminPage.complaints),
        ),
      GawaGoDrawerDestination(
        icon: Icons.assessment_outlined,
        label: 'Reports',
        selected: _page == _AdminPage.reports,
        onTap: () => setState(() => _page = _AdminPage.reports),
      ),
    ];

    return Theme(
      data: authenticatedTheme(),
      child: AuthenticatedScaffold(
        roleLabel: widget.isSuperAdmin ? 'Super Admin' : 'Administrator',
        mainDestinations: mainDestinations,
        accountDestinations: const [],
        onLogout: _logout,
        title: 'GawaGo Admin',
        child: switch (_page) {
          _AdminPage.dashboard => _AdminDashboard(repository: _repository),
          _AdminPage.verifications => _VerificationQueue(
            repository: _repository,
          ),
          _AdminPage.credentials => AdminCredentialsQueue(
            repository: _repository,
          ),
          _AdminPage.complaints => const AdminComplaintsQueue(
            repository: ComplaintRepository(),
          ),
          _AdminPage.reports => const ReportView(
            repository: ReportRepository(),
          ),
        },
      ),
    );
  }
}

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard({required this.repository});

  final AdminRepository repository;

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  late Future<AdminDashboardMetrics> _future = widget.repository
      .getDashboardMetrics();

  void _reload() {
    setState(() {
      _future = widget.repository.getDashboardMetrics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminDashboardMetrics>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final metrics = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              const Text(
                'Platform Overview',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Live operational counts from the GawaGo platform.',
                style: TextStyle(color: GawaGoColors.textMuted),
              ),
              const SizedBox(height: 16),
              ResponsiveMetricGrid(
                children: [
                  _MetricCard(
                    label: 'Total Job Postings',
                    value: '${metrics.totalJobPostings}',
                    icon: Icons.post_add_outlined,
                  ),
                  _MetricCard(
                    label: 'Open Jobs',
                    value: '${metrics.openJobs}',
                    icon: Icons.work_outline,
                  ),
                  _MetricCard(
                    label: 'Active Applications',
                    value: '${metrics.activeApplications}',
                    icon: Icons.description_outlined,
                  ),
                  _MetricCard(
                    label: 'Completed Services',
                    value: '${metrics.completedJobs}',
                    icon: Icons.task_alt_outlined,
                  ),
                  _MetricCard(
                    label: 'Cancelled Requests',
                    value: '${metrics.cancelledJobs}',
                    icon: Icons.cancel_outlined,
                  ),
                  _MetricCard(
                    label: 'Verified Users',
                    value: '${metrics.verifiedUsers}',
                    icon: Icons.verified_outlined,
                  ),
                  _MetricCard(
                    label: 'Registered Accounts',
                    value: '${metrics.totalAccounts}',
                    icon: Icons.people_outline,
                  ),
                  _MetricCard(
                    label: 'Ongoing Matches',
                    value: '${metrics.ongoingMatches}',
                    icon: Icons.handshake_outlined,
                  ),
                  _MetricCard(
                    label: 'Pending Verifications',
                    value: '${metrics.pendingVerifications}',
                    icon: Icons.pending_actions_outlined,
                  ),
                  _MetricCard(
                    label: 'Average Worker Rating',
                    value: metrics.averageRating == null
                        ? 'No ratings yet'
                        : metrics.averageRating!.toStringAsFixed(2),
                    icon: Icons.star_outline,
                    fullWidth: true,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Hiring Performance',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ResponsiveMetricGrid(
                children: [
                  _MetricCard(
                    label: 'Hiring Success Rate',
                    value: '${metrics.hiringSuccessRate.toStringAsFixed(1)}%',
                    icon: Icons.trending_up,
                  ),
                  _MetricCard(
                    label: 'Job Match Rate',
                    value: '${metrics.jobMatchRate.toStringAsFixed(1)}%',
                    icon: Icons.link,
                  ),
                  _MetricCard(
                    label: 'Hired Workers',
                    value: '${metrics.hiredWorkers}',
                    icon: Icons.badge_outlined,
                  ),
                  _MetricCard(
                    label: 'Repeat Hires',
                    value: '${metrics.repeatHires}',
                    icon: Icons.repeat,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Applications per Month',
                description:
                    'How many job applications workers sent each month over '
                    'the last six months.',
                emptyMessage: 'No applications yet.',
                items: metrics.applicationTrend,
                icon: Icons.timeline,
                maxItems: 6,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Job Postings per Month',
                description:
                    'How many jobs households posted each month over the '
                    'last six months.',
                emptyMessage: 'No job postings yet.',
                items: metrics.monthlyJobPostings,
                icon: Icons.calendar_month_outlined,
                maxItems: 6,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Jobs by Service Type',
                description:
                    'How many jobs households posted for each type of service.',
                emptyMessage: 'No job postings yet.',
                items: metrics.serviceDistribution,
                icon: Icons.category_outlined,
                maxItems: 8,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Barangay Job Demand',
                description:
                    'The barangays where households posted the most jobs.',
                emptyMessage: 'No job demand data is available yet.',
                items: metrics.barangayDemand,
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Worker Availability by Barangay',
                description: 'The barangays where the most workers are based.',
                emptyMessage: 'No worker availability data is available yet.',
                items: metrics.workerAvailability,
                icon: Icons.groups_outlined,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Average Service Rates',
                description:
                    'The average rate households offer for each service.',
                emptyMessage: 'No service-rate data is available yet.',
                items: metrics.averageRates,
                icon: Icons.payments_outlined,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Service Rate Trends',
                description:
                    'The average rate households offered on new job posts '
                    'each month over the last six months.',
                emptyMessage: 'No rate data is available yet.',
                items: metrics.pricingTrends,
                icon: Icons.show_chart,
                maxItems: 6,
              ),
              const SizedBox(height: 16),
              _AnalyticsList(
                title: 'Worker Rating Distribution',
                description: 'How many workers have each star rating.',
                emptyMessage: 'No worker ratings are available yet.',
                items: metrics.ratingDistribution,
                icon: Icons.star_outline,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: GawaGoColors.primary.withValues(alpha: 0.15),
              foregroundColor: GawaGoColors.primary,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: card) : card;
  }
}

class _AnalyticsList extends StatelessWidget {
  const _AnalyticsList({
    required this.title,
    required this.description,
    required this.emptyMessage,
    required this.items,
    required this.icon,
    this.maxItems = 5,
  });

  final String title;

  /// One line saying what the list shows (panel review 2026-10-31).
  final String description;
  final String emptyMessage;
  final List<AdminAnalyticsItem> items;
  final IconData icon;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: GawaGoColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                emptyMessage,
                style: const TextStyle(color: GawaGoColors.textMuted),
              )
            else
              ...items
                  .take(maxItems)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: GawaGoColors.text),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.unit == 'PHP'
                                ? 'PHP ${item.value.toStringAsFixed(2)}'
                                : item.value.toStringAsFixed(
                                    item.value % 1 == 0 ? 0 : 1,
                                  ),
                            style: const TextStyle(
                              color: GawaGoColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _VerificationQueue extends StatefulWidget {
  const _VerificationQueue({required this.repository});

  final AdminRepository repository;

  @override
  State<_VerificationQueue> createState() => _VerificationQueueState();
}

class _VerificationQueueState extends State<_VerificationQueue> {
  late Future<List<AdminVerificationRequest>> _future = widget.repository
      .getVerificationRequests();
  String _filter = 'pending';
  String _roleFilter = 'all';

  static const _roleTabs = {
    'all': 'All',
    'household': 'Households',
    'worker': 'Workers',
  };

  void _reload() {
    setState(() {
      _future = widget.repository.getVerificationRequests();
    });
  }

  List<AdminVerificationRequest> _byRole(
    List<AdminVerificationRequest> items,
    String role,
  ) {
    if (role == 'all') return items;
    return items
        .where((item) => item.accountRole.trim().toLowerCase() == role)
        .toList();
  }

  List<AdminVerificationRequest> _visible(
    List<AdminVerificationRequest> items,
  ) {
    final byRole = _byRole(items, _roleFilter);
    if (_filter == 'all') return byRole;
    return byRole
        .where((item) => item.status.trim().toLowerCase() == _filter)
        .toList();
  }

  Future<void> _review(AdminVerificationRequest request) async {
    final result = await showModalBottomSheet<_VerificationDecision>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GawaGoColors.surface,
      builder: (_) => _VerificationReviewSheet(
        request: request,
        repository: widget.repository,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await widget.repository.reviewVerification(
        request.id,
        action: result.action,
        reviewNote: result.note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.action == 'approve'
                  ? 'Verification approved.'
                  : 'Verification rejected.',
            ),
          ),
        );
      }
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminVerificationRequest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final visible = _visible(snapshot.data!);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              const Text(
                'Verification Queue',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Review submitted identity documents and update account verification.',
                style: TextStyle(color: GawaGoColors.textMuted),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _roleTabs.entries
                      .map(
                        (tab) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${tab.value} ${_byRole(snapshot.data!, tab.key).length}',
                            ),
                            selected: _roleFilter == tab.key,
                            onSelected: (_) =>
                                setState(() => _roleFilter = tab.key),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['pending', 'approved', 'rejected', 'all']
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(formatStatus(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 18),
              if (visible.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No verification requests in this view.'),
                  ),
                )
              else
                ...visible.map(
                  (request) => StatusCard(
                    icon: Icons.badge_outlined,
                    title: request.name.isEmpty
                        ? request.username
                        : request.name,
                    subtitle: [
                      '@${request.username}',
                      if (request.accountRole.isNotEmpty)
                        formatStatus(request.accountRole),
                      if (request.location.isNotEmpty) request.location,
                      'Submitted ${_displayDate(request.submittedAt)}',
                    ].join('\n'),
                    status: request.status,
                    emphasized:
                        request.status.trim().toLowerCase() == 'pending',
                    onTap: () => _review(request),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VerificationDecision {
  const _VerificationDecision({required this.action, required this.note});

  final String action;
  final String note;
}

class _VerificationReviewSheet extends StatefulWidget {
  const _VerificationReviewSheet({
    required this.request,
    required this.repository,
  });

  final AdminVerificationRequest request;
  final AdminRepository repository;

  @override
  State<_VerificationReviewSheet> createState() =>
      _VerificationReviewSheetState();
}

class _VerificationReviewSheetState extends State<_VerificationReviewSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Uploaded IDs live behind an authenticated route, so they are pulled as
  /// bytes and shown from memory -- Image.network cannot send the token.
  Future<void> _viewDocument(String path, String label) async {
    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await widget.repository.getVerificationDocumentBytes(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            child: Image.memory(
              bytes,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "This file can't be previewed as an image. It was "
                  'downloaded successfully -- review it on web instead.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  void _finish(String action) {
    if (action == 'reject' && _note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a reason before rejecting this request.'),
        ),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_VerificationDecision(action: action, note: _note.text));
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.name.isEmpty ? request.username : request.name,
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${request.username}',
                style: const TextStyle(color: GawaGoColors.textMuted),
              ),
              const SizedBox(height: 14),
              StatusBadge(status: request.status),
              const SizedBox(height: 16),
              _Fact(label: 'Role', value: formatStatus(request.accountRole)),
              _Fact(label: 'Email', value: request.email),
              _Fact(label: 'Phone', value: request.phone),
              _Fact(label: 'Location', value: request.location),
              _Fact(
                label: 'Skills',
                value: request.skills.isEmpty
                    ? 'Not provided'
                    : request.skills.join(', '),
              ),
              const Divider(height: 26),
              _DocumentFact(
                label: 'Primary document',
                filename: request.primaryDocument,
                onView: request.primaryDocument.isEmpty
                    ? null
                    : () => _viewDocument(
                        request.primaryDocumentPath,
                        'Primary document',
                      ),
              ),
              _DocumentFact(
                label: 'Secondary document',
                filename: request.secondaryDocument,
                onView: request.secondaryDocument.isEmpty
                    ? null
                    : () => _viewDocument(
                        request.secondaryDocumentPath,
                        'Secondary document',
                      ),
              ),
              _Fact(
                label: 'Applicant notes',
                value: request.notes.isEmpty ? 'None' : request.notes,
              ),
              if (request.reviewNote.isNotEmpty)
                _Fact(label: 'Existing admin note', value: request.reviewNote),
              if (request.status.trim().toLowerCase() == 'pending') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Review note',
                    hintText: 'Required when rejecting a request',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _finish('reject'),
                        icon: const Icon(Icons.close),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _finish('approve'),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A document row: the filename plus a View action that opens the file.
class _DocumentFact extends StatelessWidget {
  const _DocumentFact({
    required this.label,
    required this.filename,
    required this.onView,
  });

  final String label;
  final String filename;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Fact(label: label, value: filename),
          ),
          if (onView != null)
            TextButton.icon(
              onPressed: onView,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View'),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? 'Not provided' : value,
            style: const TextStyle(color: GawaGoColors.text),
          ),
        ],
      ),
    );
  }
}

String _displayDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value.isEmpty ? 'Unknown date' : value;
  return '${parsed.month}/${parsed.day}/${parsed.year}';
}
