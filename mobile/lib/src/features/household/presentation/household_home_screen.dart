import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/gawago_api.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/constants/gawago_options.dart';
import '../../../shared/utils/display_formatters.dart';
import '../../../shared/utils/map_tile_guard.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../../../shared/widgets/job_schedule_box.dart';
import '../../../shared/widgets/list_map_view_toggle.dart';
import '../../../shared/widgets/location_route_map.dart';
import '../../../shared/widgets/notification_badge.dart';
import '../../../shared/widgets/my_complaints_view.dart';
import '../../../shared/widgets/persistent_action_bar.dart';
import '../../../shared/widgets/ai_match_breakdown.dart';
import '../../../shared/widgets/authenticated_image.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../../shared/widgets/rate_review_dialog.dart';
import '../../../shared/widgets/rate_skills_dialog.dart';
import '../../../shared/widgets/report_issue_dialog.dart';
import '../../../shared/widgets/review_history.dart';
import '../../../shared/widgets/status_card.dart';
import '../../../shared/widgets/worker_cards.dart';
import '../../chat/presentation/conversations_view.dart';
import '../../worker/data/worker_models.dart';
import '../data/household_models.dart';
import '../data/household_repository.dart';
import 'household_workers_map.dart';

enum _Page {
  dashboard,
  postJob,
  jobs,
  messages,
  myReports,
  profile,
  reviews,
  verification,
  notifications,
}

class HouseholdHomeScreen extends StatefulWidget {
  const HouseholdHomeScreen({
    super.key,
    required this.onLogout,
    HouseholdRepository? repository,
  }) : repository = repository ?? const HouseholdRepository();

  final VoidCallback onLogout;
  final HouseholdRepository repository;

  @override
  State<HouseholdHomeScreen> createState() => _HouseholdHomeScreenState();
}

class _HouseholdHomeScreenState extends State<HouseholdHomeScreen>
    with WidgetsBindingObserver {
  // Read-only pages that are safe to rebuild when something new arrives;
  // forms (Post a Job, Profile, Verification) are never reset under the user.
  static const _livePages = {
    _Page.dashboard,
    _Page.jobs,
    _Page.myReports,
    _Page.notifications,
  };
  static const _pollInterval = Duration(seconds: 20);
  static const _primaryPages = [
    _Page.dashboard,
    _Page.postJob,
    _Page.jobs,
    _Page.messages,
    _Page.myReports,
    _Page.notifications,
  ];

  static const _accountPages = [_Page.profile, _Page.verification];

  HouseholdRepository get _repository => widget.repository;
  final _notificationKey = GlobalKey<_NotificationsState>();
  _Page _page = _Page.dashboard;
  final Set<_Page> _visitedPages = {_Page.dashboard};
  late Future<int> _unreadCount;
  String? _verificationStatus;
  String? _verificationRequestStatus;
  Timer? _pollTimer;
  int? _lastUnread;
  final Map<_Page, int> _pageRefresh = {};

  @override
  void initState() {
    super.initState();
    _unreadCount = _loadUnreadCount();
    _unreadCount.then((count) => _lastUnread = count, onError: (_) => null);
    _loadVerificationStatus();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// Keeps the app current with changes made elsewhere (e.g. on the website):
  /// the badge always updates, and the page on screen reloads when a new
  /// notification signals that its data changed.
  Future<void> _poll() async {
    final int count;
    try {
      count = await _loadUnreadCount();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final changed = _lastUnread != null && count > _lastUnread!;
    _lastUnread = count;
    setState(() {
      _unreadCount = Future.value(count);
      if (changed && _livePages.contains(_page)) {
        _pageRefresh[_page] = (_pageRefresh[_page] ?? 0) + 1;
      }
    });
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final profile = await _repository.getProfile();
      if (!mounted) return;
      setState(() {
        _verificationStatus = profile.verificationStatus;
        _verificationRequestStatus = profile.verificationRequestStatus;
      });
    } catch (_) {
      // Keep the generic "Get Verified" label; the page itself shows status.
    }
  }

  String _navLabel(_Page page) => page == _Page.verification
      ? verificationNavLabel(_verificationStatus, _verificationRequestStatus)
      : _title(page);

  Future<int> _loadUnreadCount() => _repository.getUnreadNotificationCount();

  void _refreshUnreadCount() {
    setState(() {
      _unreadCount = _loadUnreadCount();
    });
  }

  Future<void> _logout() async {
    await GawaGoApi.logout();
    await SessionStorage.clear();
    widget.onLogout();
  }

  void _select(_Page page) {
    setState(() {
      _page = page;
      _visitedPages.add(page);
    });
  }

  // Bumps only the affected page's own key instead of a global counter that
  // used to rekey every visited page in the IndexedStack -- including ones
  // with their own unsaved local state (a Post Job draft, Find Jobs
  // filters), wiping them on any unrelated action anywhere in the app
  // (F-11). Defaults to whichever page is on screen, since _changed is
  // always called as a direct result of something the user just did there;
  // callers acting from outside the IndexedStack (a pushed detail route)
  // pass the page that actually needs to refresh.
  void _changed({_Page? page}) {
    final target = page ?? _page;
    setState(() {
      _pageRefresh[target] = (_pageRefresh[target] ?? 0) + 1;
      _unreadCount = _loadUnreadCount();
    });
    _loadVerificationStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: authenticatedTheme(),
      child: AuthenticatedScaffold(
        title: 'GawaGo',
        roleLabel: 'Account',
        mainDestinations: _primaryPages
            .map(
              (page) => GawaGoDrawerDestination(
                icon: _icon(page),
                label: _title(page),
                selected: page == _page,
                onTap: () => _select(page),
              ),
            )
            .toList(),
        accountDestinations: _accountPages
            .map(
              (page) => GawaGoDrawerDestination(
                icon: _icon(page),
                label: _navLabel(page),
                selected: page == _page,
                onTap: () => _select(page),
              ),
            )
            .toList(),
        onLogout: _logout,
        actions: _page == _Page.notifications
            ? [
                IconButton(
                  tooltip: 'Filter notifications by date',
                  onPressed: () => _notificationKey.currentState?.chooseDate(),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Notification actions',
                  onSelected: (value) {
                    if (value == 'mark_all') {
                      _notificationKey.currentState?.markAllRead();
                    } else {
                      _notificationKey.currentState?.clearDateFilter();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'mark_all',
                      child: ListTile(
                        leading: Icon(Icons.done_all),
                        title: Text('Mark all as read'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (_notificationKey.currentState?.hasDateFilter ?? false)
                      const PopupMenuItem(
                        value: 'clear_filter',
                        child: ListTile(
                          leading: Icon(Icons.filter_alt_off_outlined),
                          title: Text('Clear date filter'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ]
            : [
                FutureBuilder<int>(
                  future: _unreadCount,
                  builder: (context, snapshot) => IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => _select(_Page.notifications),
                    icon: NotificationBadge(
                      count: snapshot.data ?? 0,
                      child: const Icon(Icons.notifications_none),
                    ),
                  ),
                ),
              ],
        child: IndexedStack(
          index: _Page.values.indexOf(_page),
          children: [
            for (final page in _Page.values)
              _visitedPages.contains(page)
                  ? KeyedSubtree(
                      key: ValueKey('${page.name}-${_pageRefresh[page] ?? 0}'),
                      child: _buildPage(page),
                    )
                  : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_Page page) {
    return switch (page) {
      _Page.dashboard => _Dashboard(
        repository: _repository,
        onNavigate: _select,
      ),
      _Page.postJob => _PostJob(
        repository: _repository,
        onCancel: () => _select(_Page.dashboard),
        onCreated: _openJobMatches,
        onNetworkUncertainty: () => _select(_Page.jobs),
      ),
      _Page.jobs => _MyJobs(
        repository: _repository,
        onChanged: _changed,
        onPostNew: () => _select(_Page.postJob),
      ),
      _Page.messages => const ConversationsView(role: 'household'),
      _Page.myReports => _HouseholdMyReports(repository: _repository),
      _Page.profile => _Profile(repository: _repository, onSaved: _changed),
      _Page.reviews => ReviewHistory(
        receivedLoader: _repository.getReceivedReviews,
        givenLoader: _repository.getGivenReviews,
        receivedTitle: 'Feedback from Workers',
        givenTitle: 'Reviews You Gave Workers',
      ),
      _Page.verification => _Verification(
        repository: _repository,
        onSubmitted: _changed,
      ),
      _Page.notifications => _Notifications(
        key: _notificationKey,
        repository: _repository,
        onOpenJob: _openJob,
        onToolbarChanged: () => setState(() {}),
        onNotificationsChanged: _refreshUnreadCount,
      ),
    };
  }

  Future<void> _openJob(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobDetail(
          repository: _repository,
          jobId: id,
          onChanged: () => _changed(page: _Page.jobs),
        ),
      ),
    );
  }

  /// Straight from posting into AI-matched workers for the new job. Landing
  /// on My Jobs first buried the recommendations three taps deep, which is
  /// exactly when they are most useful.
  Future<void> _openJobMatches(HouseholdJob job) async {
    _changed(page: _Page.jobs);
    setState(() {
      _page = _Page.jobs;
      _visitedPages.add(_Page.jobs);
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobMatches(
          repository: _repository,
          job: job,
          onChanged: _changed,
          onOpenJob: _openJob,
        ),
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.repository, required this.onNavigate});

  final HouseholdRepository repository;
  final ValueChanged<_Page> onNavigate;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<(HouseholdProfile, List<HouseholdJob>)> _future = _load();

  Future<(HouseholdProfile, List<HouseholdJob>)> _load() async {
    final values = await Future.wait([
      widget.repository.getProfile(),
      widget.repository.getMyJobs(),
    ]);
    return (values[0] as HouseholdProfile, values[1] as List<HouseholdJob>);
  }

  void _reload() {
    // A block body, not `() => _future = _load()` -- an arrow body would
    // make the closure itself return the Future being assigned, which
    // Flutter's setState() explicitly rejects at runtime ("setState()
    // callback argument returned a Future").
    setState(() {
      _future = _load();
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
  }

  Future<void> _openJobDetail(int jobId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobDetail(
          repository: widget.repository,
          jobId: jobId,
          onChanged: _reload,
        ),
      ),
    );
    _reload();
  }

  Future<void> _browseWorkers(HouseholdJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobMatches(
          repository: widget.repository,
          job: job,
          onChanged: _reload,
          onOpenJob: _openJobDetail,
        ),
      ),
    );
    _reload();
  }

  final Set<int> _jobsInFlight = {};

  Future<void> _markDone(HouseholdJob job) async {
    // Claimed before the dialog: a second tap lands before the first
    // dialog covers the button and would open (and send) a second one.
    if (!_jobsInFlight.add(job.id)) return;
    try {
      final confirmed = await _confirmDialog(
        context,
        title: 'Mark this job as done?',
        message:
            "The worker will be notified and you can both leave a review. "
            "This can't be undone.",
      );
      if (!confirmed) return;
      try {
        await widget.repository.updateJobStatus(job.id, 'completed');
        _reload();
      } catch (error) {
        _showError(error);
      }
    } finally {
      _jobsInFlight.remove(job.id);
    }
  }

  Future<void> _cancelJob(HouseholdJob job) async {
    // Claimed before the dialog: a second tap lands before the first
    // dialog covers the button and would open (and send) a second one.
    if (!_jobsInFlight.add(job.id)) return;
    try {
      final confirmed = await _confirmDialog(
        context,
        title: 'Cancel this job?',
        message: "This can't be undone.",
        destructive: true,
      );
      if (!confirmed) return;
      try {
        await widget.repository.updateJobStatus(job.id, 'cancelled');
        _reload();
      } catch (error) {
        _showError(error);
      }
    } finally {
      _jobsInFlight.remove(job.id);
    }
  }

  Future<void> _rateWorker(HouseholdJob job) async {
    final worker = _workerToReview(job);
    if (worker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No worker is assigned to this job yet.')),
      );
      return;
    }
    final submitted = await showRateReviewDialog(
      context: context,
      workerName: worker.workerName,
      workerInitial: _initial(worker.workerName),
      workerVerified:
          worker.workerVerificationStatus.toLowerCase() == 'verified',
      onSubmit:
          ({
            required rating,
            required feedback,
            qualityOfWork,
            punctuality,
            communication,
            professionalism,
          }) => widget.repository.reviewWorker(
            job,
            worker,
            rating: rating,
            feedback: feedback,
            qualityOfWork: qualityOfWork,
            punctuality: punctuality,
            communication: communication,
            professionalism: professionalism,
          ),
    );
    if (submitted) {
      if (mounted) {
        await _offerSkillRatings(context, widget.repository, job, worker);
      }
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Review submitted.')));
      }
    }
  }

  Future<void> _viewApplicants(HouseholdJob job) {
    return showApplicantsDialog(
      context: context,
      job: job,
      repository: widget.repository,
      onChanged: _reload,
      onOpenApplicant: (application) => _openApplicantDetail(job, application),
    );
  }

  /// "View Profile" on an applicant card opens that worker's profile, not the
  /// job it was reached from -- the job is already on screen behind it.
  Future<void> _openApplicantDetail(
    HouseholdJob job,
    HouseholdApplication application,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ApplicantDetail(
          job: job,
          application: application,
          repository: widget.repository,
          onChanged: _reload,
        ),
      ),
    );
    _reload();
  }

  /// "Report" on a completed job opens the complaint form directly. The job
  /// detail screen has its own copy of this, but a household should not have
  /// to go looking for it.
  Future<void> _reportJob(HouseholdJob job) async {
    final submitted = await showReportIssueDialog(
      context: context,
      jobId: job.id,
      jobTitle: job.title,
      isHousehold: true,
      applicants: job.applications
          .map(
            (application) => ReportApplicantOption(
              workerId: application.workerId,
              label: application.workerName.isEmpty
                  ? application.workerUsername
                  : application.workerName,
            ),
          )
          .toList(),
    );
    if (!submitted || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Complaint submitted. Our admin team will review it.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(HouseholdProfile, List<HouseholdJob>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final profile = snapshot.data!.$1;
        final jobs = snapshot.data!.$2;
        // Mirrors web's inProcessHouseholdJobs/pendingHouseholdReviewJobs
        // split (AppViews.jsx): a job lives in exactly one of "in process"
        // or history, moving over the moment it's Completed or Cancelled.
        final inProcessJobs = jobs.where(_isInProgressDashboardJob).toList();
        final pendingReviewJobs = jobs
            .where(
              (job) =>
                  _normalizedJobStatus(job.status) == 'completed' &&
                  job.canReview,
            )
            .toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _HouseholdWelcomeBanner(profile: profile),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Jobs that are still in motion — waiting on applicants, '
                  'in progress, or waiting on you.',
                  style: TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => widget.onNavigate(_Page.postJob),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Post a New Job'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GawaGoColors.primary,
                    foregroundColor: GawaGoColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: GawaGoColors.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'IN PROCESS · ${inProcessJobs.length}',
                style: const TextStyle(
                  color: GawaGoColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              if (inProcessJobs.isEmpty)
                _HouseholdEmptyJobsCard(
                  onTap: () => widget.onNavigate(_Page.postJob),
                )
              else
                ...inProcessJobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _InProcessJobCard(
                      job: job,
                      onBrowseWorkers: () => _browseWorkers(job),
                      onViewApplicants: () => _viewApplicants(job),
                      onMarkDone: () => _markDone(job),
                      onCancel: () => _cancelJob(job),
                    ),
                  ),
                ),
              if (pendingReviewJobs.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'COMPLETED · ${pendingReviewJobs.length}',
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 12),
                ...pendingReviewJobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _PendingReviewJobCard(
                      job: job,
                      onRate: () => _rateWorker(job),
                      onReport: () => _reportJob(job),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: GawaGoColors.danger)
              : null,
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _HouseholdWelcomeBanner extends StatelessWidget {
  const _HouseholdWelcomeBanner({required this.profile});

  final HouseholdProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Welcome, ${profile.fullName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: gawagoHeading(fontSize: 26, height: 1.2),
      ),
    );
  }
}

enum _ProcessTone { assigned, applicants, open }

/// One "IN PROCESS" card on the household Dashboard -- mirrors web's
/// .household-process-card (AppViews.jsx / main.css) icon-coded status,
/// assigned-worker row, and per-status action, instead of the old flat
/// label/value row card.
class _InProcessJobCard extends StatelessWidget {
  const _InProcessJobCard({
    required this.job,
    required this.onBrowseWorkers,
    required this.onViewApplicants,
    required this.onMarkDone,
    required this.onCancel,
  });

  final HouseholdJob job;
  final VoidCallback onBrowseWorkers;
  final VoidCallback onViewApplicants;
  final VoidCallback onMarkDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pendingCount = job.applications
        .where((application) => application.status == 'pending')
        .length;
    final assignedApp = _selectedWorker(job);
    final isAssigned =
        assignedApp != null &&
        (assignedApp.status == 'hired' || assignedApp.status == 'completed');
    final hasApplicants = !isAssigned && pendingCount > 0;
    // A sent hire request is still an open thread on this job: without its own
    // state the card would claim nobody applied the moment the household
    // asked someone.
    final requestedCount = job.applications
        .where((application) => application.status == 'hire_requested')
        .length;
    final awaitingReply = !isAssigned && !hasApplicants && requestedCount > 0;

    final tone = isAssigned || awaitingReply
        ? _ProcessTone.assigned
        : hasApplicants
        ? _ProcessTone.applicants
        : _ProcessTone.open;

    final (Color bg, Color fg, IconData icon) = switch (tone) {
      _ProcessTone.assigned => (
        const Color(0x479EBF5E),
        GawaGoColors.leafDeep,
        Icons.access_time_rounded,
      ),
      _ProcessTone.applicants => (
        const Color(0x2E9EBF5E),
        GawaGoColors.leafDeep,
        Icons.groups_outlined,
      ),
      _ProcessTone.open => (
        const Color(0x2E9EBF5E),
        GawaGoColors.leafDeep,
        Icons.search_rounded,
      ),
    };
    final dotColor = tone == _ProcessTone.assigned
        ? GawaGoColors.leafDeep
        : GawaGoColors.primary;

    final statusLabel = isAssigned
        ? 'In progress'
        : hasApplicants
        ? '$pendingCount applicant${pendingCount == 1 ? '' : 's'} waiting'
        : awaitingReply
        ? '$requestedCount request${requestedCount == 1 ? '' : 's'} sent — '
              'waiting for a reply'
        : 'Just posted — no applicants yet';

    final workerName = assignedApp?.workerName ?? '';
    final isVerified =
        (assignedApp?.workerVerificationStatus ?? '').toLowerCase() ==
        'verified';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GawaGoColors.line),
        boxShadow: gawagoCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, style: gawagoHeading(fontSize: 16)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: GawaGoColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: assignedApp != null
                    ? GawaGoColors.primary
                    : GawaGoColors.surfaceMuted,
                child: assignedApp != null
                    ? Text(
                        _initial(workerName),
                        style: const TextStyle(
                          color: GawaGoColors.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      )
                    : const Icon(
                        Icons.question_mark,
                        size: 14,
                        color: GawaGoColors.textFaint,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignedApp != null ? workerName : 'No worker hired yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: assignedApp != null
                            ? GawaGoColors.ink
                            : GawaGoColors.textFaint,
                      ),
                    ),
                    if (assignedApp != null)
                      Text(
                        isVerified ? 'Verified' : 'Not Yet Verified',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: GawaGoColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              _rateLabel(job),
              job.locationLabel.trim().isEmpty
                  ? 'Location not set'
                  : _barangay(job),
            ].join(' · '),
            style: const TextStyle(
              fontSize: 12.5,
              color: GawaGoColors.textMuted,
            ),
          ),
          if ((job.jobStartDate ?? '').isNotEmpty ||
              (job.jobEndDate ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            JobScheduleBox(
              startDate: job.jobStartDate,
              endDate: job.jobEndDate,
              workingDays: job.estimatedWorkingDays,
            ),
          ],
          const SizedBox(height: 12),
          if (isAssigned) ...[
            // The household marks a job done (AGENTS.md I.A); the backend
            // says when that's allowed and, if not yet, why.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: job.canMarkDone ? onMarkDone : null,
                style: FilledButton.styleFrom(
                  backgroundColor: GawaGoColors.primary,
                  foregroundColor: GawaGoColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Mark as done'),
              ),
            ),
            if (job.markDoneNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GawaGoColors.leafTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  job.markDoneNote,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: GawaGoColors.textMuted,
                  ),
                ),
              ),
            ],
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: hasApplicants || awaitingReply
                    ? onViewApplicants
                    : onBrowseWorkers,
                icon: Icon(
                  hasApplicants || awaitingReply
                      ? Icons.groups_outlined
                      : Icons.search,
                  size: 16,
                ),
                label: Text(
                  hasApplicants || awaitingReply
                      ? 'View Applicants'
                      : 'Browse Workers',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: GawaGoColors.leafDeep,
                  side: const BorderSide(
                    color: GawaGoColors.primary,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (!hasApplicants) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GawaGoColors.leafTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  awaitingReply
                      ? "We'll let you know as soon as they accept or decline."
                      : "We'll notify you as soon as a worker applies.",
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: GawaGoColors.textMuted,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: GawaGoColors.danger,
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'Cancel Job',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A completed-but-unreviewed job on the Dashboard -- mirrors web's
/// "Completed" reminder section (AppViews.jsx, roadmap item "Show View
/// Details on My Jobs for completed-but-unreviewed jobs"). It doesn't leave
/// My Jobs though: that page is the complete record, rated or not.
class _PendingReviewJobCard extends StatelessWidget {
  const _PendingReviewJobCard({
    required this.job,
    required this.onRate,
    required this.onReport,
  });

  final HouseholdJob job;
  final VoidCallback onRate;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final assignedApp = _selectedWorker(job);
    final workerName = assignedApp?.workerName ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GawaGoColors.leafTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: GawaGoColors.leafDeep,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, style: gawagoHeading(fontSize: 16)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: GawaGoColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Completed · Rate your worker',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GawaGoColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: assignedApp != null
                    ? GawaGoColors.primary
                    : GawaGoColors.surfaceMuted,
                child: Text(
                  assignedApp != null ? _initial(workerName) : '?',
                  style: TextStyle(
                    color: assignedApp != null
                        ? GawaGoColors.onPrimary
                        : GawaGoColors.textFaint,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  assignedApp != null
                      ? workerName
                      : 'Worker record unavailable',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: GawaGoColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_rateLabel(job)} · '
            '${job.locationLabel.trim().isEmpty ? "Location not set" : _barangay(job)}',
            style: const TextStyle(
              fontSize: 12.5,
              color: GawaGoColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: assignedApp != null ? onRate : null,
                  icon: const Icon(Icons.star_rounded, size: 16),
                  label: const Text('Rate & Review'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GawaGoColors.primary,
                    foregroundColor: GawaGoColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: const Text('Complain'),
                style: TextButton.styleFrom(
                  foregroundColor: GawaGoColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JobStatusPill extends StatelessWidget {
  const _JobStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => GawaGoColors.leafDeep,
      'cancelled' => GawaGoColors.textMuted,
      'assigned' || 'completion_requested' => GawaGoColors.leafDeep,
      _ => GawaGoColors.leafDeep,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        formatStatus(status),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HouseholdEmptyJobsCard extends StatelessWidget {
  const _HouseholdEmptyJobsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No posted jobs yet.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.post_add),
            label: const Text('Post a Job'),
          ),
        ],
      ),
    );
  }
}

String _barangay(HouseholdJob job) {
  final label = job.locationLabel.trim();
  if (label.isEmpty) return 'Not specified';
  return label.split(',').first.trim();
}

String _profileBarangay(HouseholdProfile profile) =>
    _barangayFromText(profile.locationLabel) ?? 'Not set';

String? _barangayFromText(String value) {
  final parts = value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  for (final part in parts) {
    final match = gawagoBarangays
        .where((barangay) => barangay.toLowerCase() == part.toLowerCase())
        .firstOrNull;
    if (match != null) return match;
  }
  return null;
}

String _streetFromLocation(String value) {
  final barangay = _barangayFromText(value);
  return value
      .split(',')
      .map((part) => part.trim())
      .where(
        (part) =>
            part.isNotEmpty &&
            part.toLowerCase() != barangay?.toLowerCase() &&
            part.toLowerCase() != 'tayabas city' &&
            part.toLowerCase() != 'quezon',
      )
      .join(', ');
}

String _rateLabel(HouseholdJob job) =>
    'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}';

String _normalizedJobStatus(String status) => status
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

// Matches web's inProcessHouseholdJobs (AppViews.jsx): a job lives in
// exactly one of "in process" or history, moving over the moment it's
// Completed or Cancelled -- open jobs belong here too, not just assigned
// ones, since they still need the household's attention.
bool _isInProgressDashboardJob(HouseholdJob job) {
  final status = _normalizedJobStatus(job.status);
  return status != 'completed' && status != 'cancelled';
}

/// The worker a Rate/Review action is for: on a job with several hired
/// workers, the first one this household hasn't reviewed yet -- always taking
/// the first hired worker left the others unreviewable.
HouseholdApplication? _workerToReview(HouseholdJob job) {
  for (final application in job.applications) {
    if (application.householdCanReview) return application;
  }
  return _selectedWorker(job);
}

HouseholdApplication? _selectedWorker(HouseholdJob job) {
  for (final status in ['hired', 'completed', 'hire_requested']) {
    for (final application in job.applications) {
      if (application.status == status) return application;
    }
  }
  return null;
}

String _initial(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? 'W' : normalized.characters.first.toUpperCase();
}

String _scheduleLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'Not specified';
  final parsed = DateTime.tryParse(normalized);
  return parsed == null ? normalized : formatLocalDateTime(normalized);
}

String _jobScheduleDisplay(HouseholdJob job) {
  final raw = _jobScheduleRaw(job);
  final match = RegExp(
    r'(\d{4}-\d{2}-\d{2}).*?(\d{2}:\d{2})(?::\d{2})?',
  ).firstMatch(raw);
  if (match == null) return _scheduleLabel(raw);
  final dateTime = DateTime.tryParse('${match.group(1)} ${match.group(2)}:00');
  if (dateTime == null) return raw;
  return formatLocalDateTime(dateTime.toIso8601String());
}

String _jobScheduleRaw(HouseholdJob job) =>
    job.schedule.trim().isEmpty ? 'the selected schedule' : job.schedule.trim();

class _PostJob extends StatefulWidget {
  const _PostJob({
    required this.repository,
    required this.onCreated,
    required this.onCancel,
    this.onNetworkUncertainty,
  });

  final HouseholdRepository repository;
  final ValueChanged<HouseholdJob> onCreated;
  final VoidCallback onCancel;

  /// Called when the connection dropped before the server confirmed, so the
  /// job may or may not exist and the household should go and look.
  final VoidCallback? onNetworkUncertainty;

  @override
  State<_PostJob> createState() => _PostJobState();
}

class _PostJobState extends State<_PostJob> {
  late Future<HouseholdProfile> _profileFuture = widget.repository.getProfile();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _rate = TextEditingController();
  final _slots = TextEditingController(text: '1');
  final _workingDays = TextEditingController();
  // The service typed when "Other" is picked; "Other" is never sent.
  final _customService = TextEditingController();
  String? _skill;
  String? _barangay;
  String _scheduleType = 'One-Time';
  String _rateType = 'Per Day';
  String _geographicBoundary = '1km';
  // Mirrors the `distanceKmMap` in the web client's useGawaGoActions.js so
  // both clients send the same hard distance limit for the same radius label.
  static const Map<String, double> _geographicBoundaryDistanceKm = {
    '1km': 1.0,
    '2km': 2.0,
    '5km': 5.0,
    '10km': 10.0,
    'unlimited': 999999,
  };
  DateTime? _startDate;
  DateTime? _endDate;
  LatLng? _pin;
  final List<String> _imagePaths = [];
  bool _posting = false;

  // Mirrors the web client's JobImageUpload (maxImages=5, maxFileSize=5MB) --
  // the backend enforces neither, so without this mobile could post jobs
  // with an unbounded number of arbitrarily large images.
  static const int _maxJobImages = 5;
  static const int _maxJobImageBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _rate.dispose();
    _slots.dispose();
    _workingDays.dispose();
    _customService.dispose();
    super.dispose();
  }

  /// Clears everything that describes one job. The location and pin are
  /// the household's own address, so they stay for the next posting.
  void _resetJobFields() {
    setState(() {
      _title.clear();
      _description.clear();
      _rate.clear();
      _slots.text = '1';
      _workingDays.clear();
      _customService.clear();
      _skill = null;
      _scheduleType = 'One-Time';
      _rateType = 'Per Day';
      _geographicBoundary = '1km';
      _startDate = null;
      _endDate = null;
      _imagePaths.clear();
    });
  }

  Future<void> _pickImages() async {
    const group = XTypeGroup(
      label: 'Job reference images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;

    final oversized = <String>[];
    final accepted = <String>[];
    for (final file in files) {
      // XFile.length() also works in the web build, where dart:io File
      // throws.
      if (await file.length() > _maxJobImageBytes) {
        oversized.add(file.name);
      } else {
        accepted.add(file.path);
      }
    }
    if (!mounted) return;

    final combined = {..._imagePaths, ...accepted}.toList();
    final overflow = combined.length - _maxJobImages;
    if (overflow > 0) {
      combined.removeRange(combined.length - overflow, combined.length);
    }

    setState(() {
      _imagePaths
        ..clear()
        ..addAll(combined);
    });

    if (oversized.isNotEmpty) {
      _message('${oversized.join(', ')}: exceeds 5 MB and was not added.');
    } else if (overflow > 0) {
      _message('You can only upload up to $_maxJobImages images.');
    }
  }

  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied.');
      }
      final value = await Geolocator.getCurrentPosition();
      _setPin(LatLng(value.latitude, value.longitude));
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    }
  }

  void _setPin(LatLng point) {
    setState(() => _pin = point);
  }

  /// The service the job is for: the picked catalog skill, or the typed one
  /// when "Other" is picked. Null when nothing usable was chosen.
  String? get _serviceType {
    final skill = _skill;
    if (skill == null) return null;
    if (!isOtherSkillChoice(skill)) return skill;
    final typed = resolveWorkerSkills([gawagoOtherSkill], _customService.text);
    return typed.isEmpty ? null : typed.first;
  }

  Future<void> _submit() async {
    if (_posting) return;
    if (_skill != null && isOtherSkillChoice(_skill!) && _serviceType == null) {
      _message('Type the service you need instead of "Other".');
      return;
    }
    final serviceType = _serviceType;
    if (_title.text.trim().isEmpty ||
        serviceType == null ||
        _barangay == null ||
        _startDate == null ||
        _location.text.trim().isEmpty ||
        _pin == null ||
        (double.tryParse(_rate.text) ?? 0) <= 0) {
      _message('Complete all required job, schedule, rate, and map fields.');
      return;
    }
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _message('Job end date must be on or after the job start date.');
      return;
    }
    // A one-day job ends on the day it starts, so only check that the day
    // count fits the schedule -- this mirrors the backend's rule.
    if (_startDate != null && _endDate != null) {
      final span = _endDate!.difference(_startDate!).inDays + 1;
      final workingDays = int.tryParse(_workingDays.text.trim());
      if (workingDays != null && workingDays > span) {
        _message(
          'That is more working days than the $span-day schedule allows.',
        );
        return;
      }
    }
    final slots = int.tryParse(_slots.text.trim());
    if (_slots.text.trim().isNotEmpty &&
        (slots == null || slots < 1 || slots > 50)) {
      _message('Workers needed must be a number between 1 and 50.');
      return;
    }
    final workingDaysText = _workingDays.text.trim();
    if (workingDaysText.isNotEmpty) {
      final parsed = int.tryParse(workingDaysText);
      if (parsed == null || parsed < 1 || parsed > 366) {
        _message('Estimated working days must be a number between 1 and 366.');
        return;
      }
    }
    setState(() => _posting = true);
    try {
      final locationLabel = '${_barangay!}, ${_location.text.trim()}';
      final created = await widget.repository.createJob({
        'title': _title.text.trim(),
        'job_type': serviceType,
        'required_skill': serviceType,
        'schedule_type': _scheduleType,
        'description': _description.text.trim(),
        'rate_type': switch (_rateType) {
          'Per Hour' => 'per_hour',
          'Fixed Rate' => 'fixed',
          _ => 'per_day',
        },
        'location_label': locationLabel,
        'latitude': _coordinateForApi(_pin!.latitude),
        'longitude': _coordinateForApi(_pin!.longitude),
        'service_rate': _rate.text.trim(),
        'worker_slots': int.tryParse(_slots.text) ?? 1,
        if (_startDate != null)
          'job_start_date': _startDate!.toIso8601String().split('T').first,
        if (_endDate != null)
          'job_end_date': _endDate!.toIso8601String().split('T').first,
        if (int.tryParse(_workingDays.text) != null)
          'estimated_working_days': int.parse(_workingDays.text),
        'geographic_boundary': _geographicBoundary,
        // Without this the backend defaults max_distance_km to 1.0 no matter
        // what radius is picked here, so a "10km" job only ever matched
        // workers within 1 km. Mirrors the mapping in the web client.
        'max_distance_km':
            _geographicBoundaryDistanceKm[_geographicBoundary] ?? 1.0,
      }, imagePaths: _imagePaths);
      // This page stays alive in the IndexedStack, so without a reset coming
      // back to it showed the last job filled in, one tap from a duplicate.
      if (mounted) _resetJobFields();
      widget.onCreated(created);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.type == ApiErrorType.network) {
        // A timeout does not mean the job was not created: the server may
        // have finished after the client gave up, and posting again would
        // create a duplicate. Send the household to their job list to check
        // rather than inviting a second submission.
        _message(
          'We lost the connection before confirming. Check My Jobs -- the '
          'job may already have been posted.',
        );
        widget.onNetworkUncertainty?.call();
      } else {
        _message(friendlyApiError(error));
      }
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HouseholdProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            // markNeedsBuild() alone just rebuilt against the same already-
            // failed Future -- it never actually retried the request (F-25).
            onRetry: () => setState(() {
              _profileFuture = widget.repository.getProfile();
            }),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final profile = snapshot.data!;
        if (profile.verificationStatus.trim().toLowerCase() != 'verified') {
          return ListView(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 28),
            children: [
              _PostJobShell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Your household must be verified before posting a job.',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Submit your verification documents from the Get '
                      'Verified menu, then come back here once approved.',
                      style: TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final profilePin = profile.latitude == null || profile.longitude == null
            ? null
            : LatLng(profile.latitude!, profile.longitude!);
        if (_pin == null && profilePin != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pin == null) {
              setState(() => _pin = profilePin);
            }
          });
        }
        if (_location.text.isEmpty && profile.locationLabel.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _location.text.isNotEmpty) return;
            final parts = profile.locationLabel
                .split(',')
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .toList();
            setState(() {
              final matchedBarangay = parts
                  .where((part) => gawagoBarangays.contains(part))
                  .firstOrNull;
              _barangay ??= matchedBarangay;
              _location.text = parts
                  .where((part) => part != matchedBarangay)
                  .join(', ');
            });
          });
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 28),
          children: [
            _PostJobShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Post a New Job',
                    style: TextStyle(
                      fontFamily: GawaGoColors.fontHeading,
                      color: GawaGoColors.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 720;
                      final fields = _PostJobFields(
                        title: _title,
                        description: _description,
                        street: _location,
                        rate: _rate,
                        slots: _slots,
                        workingDays: _workingDays,
                        customService: _customService,
                        serviceType: _skill,
                        scheduleType: _scheduleType,
                        barangay: _barangay,
                        rateType: _rateType,
                        geographicBoundary: _geographicBoundary,
                        startDateLabel: _startDate == null
                            ? 'mm/dd/yyyy'
                            : '${_startDate!.month.toString().padLeft(2, '0')}/${_startDate!.day.toString().padLeft(2, '0')}/${_startDate!.year}',
                        endDateLabel: _endDate == null
                            ? 'mm/dd/yyyy'
                            : '${_endDate!.month.toString().padLeft(2, '0')}/${_endDate!.day.toString().padLeft(2, '0')}/${_endDate!.year}',
                        onServiceChanged: (value) =>
                            setState(() => _skill = value),
                        onScheduleChanged: (value) => setState(
                          () => _scheduleType = value ?? _scheduleType,
                        ),
                        // A job in another barangay is pinned there, not at
                        // the household's home pin.
                        onBarangayChanged: (value) => setState(() {
                          if (value != _barangay) _pin = null;
                          _barangay = value;
                        }),
                        onRateTypeChanged: (value) =>
                            setState(() => _rateType = value ?? _rateType),
                        onGeographicBoundaryChanged: (value) => setState(
                          () => _geographicBoundary =
                              value ?? _geographicBoundary,
                        ),
                        onPickStartDate: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (value != null) setState(() => _startDate = value);
                        },
                        onPickEndDate: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: _startDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (value != null) setState(() => _endDate = value);
                        },
                      );
                      final map = _PostJobMapPanel(
                        pin: _pin,
                        profilePin: profilePin,
                        focus: barangayCenter(_barangay),
                        onSetPin: _setPin,
                        onLocate: _locate,
                      );
                      if (!wide) {
                        return Column(
                          children: [fields, const SizedBox(height: 18), map],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fields),
                          const SizedBox(width: 24),
                          Expanded(child: map),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _PostJobImagesBox(
                    imagePaths: _imagePaths,
                    onPickImages: _pickImages,
                    onRemove: (index) =>
                        setState(() => _imagePaths.removeAt(index)),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _posting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: GawaGoColors.primary,
                          foregroundColor: GawaGoColors.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(_posting ? 'Posting...' : 'Post Job'),
                      ),
                      OutlinedButton(
                        onPressed: _posting ? null : widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GawaGoColors.ink,
                          side: const BorderSide(color: GawaGoColors.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PostJobShell extends StatelessWidget {
  const _PostJobShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: child,
    );
  }
}

class _PostJobFields extends StatelessWidget {
  const _PostJobFields({
    required this.title,
    required this.description,
    required this.street,
    required this.rate,
    required this.slots,
    required this.workingDays,
    required this.customService,
    required this.serviceType,
    required this.scheduleType,
    required this.barangay,
    required this.rateType,
    required this.geographicBoundary,
    required this.startDateLabel,
    required this.endDateLabel,
    required this.onServiceChanged,
    required this.onScheduleChanged,
    required this.onBarangayChanged,
    required this.onRateTypeChanged,
    required this.onGeographicBoundaryChanged,
    required this.onPickStartDate,
    required this.onPickEndDate,
  });

  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController street;
  final TextEditingController rate;
  final TextEditingController slots;
  final TextEditingController workingDays;
  final TextEditingController customService;
  final String? serviceType;
  final String scheduleType;
  final String? barangay;
  final String rateType;
  final String geographicBoundary;
  final String startDateLabel;
  final String endDateLabel;
  final ValueChanged<String?> onServiceChanged;
  final ValueChanged<String?> onScheduleChanged;
  final ValueChanged<String?> onBarangayChanged;
  final ValueChanged<String?> onRateTypeChanged;
  final ValueChanged<String?> onGeographicBoundaryChanged;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PostJobInput(
          label: 'Job Title',
          controller: title,
          hint: 'e.g. House Cleaning - 3 Bedroom',
        ),
        _PostJobTwoColumn(
          left: _PostJobDropdown(
            label: 'Service Type',
            value: serviceType,
            hint: '---Select Service---',
            items: gawagoSkills,
            onChanged: onServiceChanged,
          ),
          right: _PostJobDropdown(
            label: 'Schedule Type',
            value: scheduleType,
            items: const ['One-Time', 'Recurring'],
            onChanged: onScheduleChanged,
          ),
        ),
        if (serviceType != null && isOtherSkillChoice(serviceType!))
          _PostJobInput(
            key: const ValueKey('post-job-custom-service'),
            label: 'Specify Service Type',
            controller: customService,
            hint: 'e.g. Pet Grooming',
          ),
        _PostJobInput(
          label: 'Job Description',
          controller: description,
          hint: 'Describe the job in detail...',
          lines: 4,
        ),
        _PostJobTwoColumn(
          left: _PostJobDropdown(
            label: 'Barangay',
            value: barangay,
            hint: '---Select Barangay---',
            items: gawagoBarangays,
            onChanged: onBarangayChanged,
          ),
          right: _PostJobInput(
            label: 'Street / House No.',
            controller: street,
            hint: 'QZ, Philippines',
          ),
        ),
        _PostJobTwoColumn(
          left: _PostJobInput(
            label: 'Workers Needed',
            controller: slots,
            keyboardType: TextInputType.number,
          ),
          right: _PostJobInput(
            label: 'Offered Rate',
            controller: rate,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 176,
            child: _PostJobDropdown(
              label: 'Rate Type',
              value: rateType,
              items: const ['Per Day', 'Per Hour', 'Fixed Rate'],
              onChanged: onRateTypeChanged,
            ),
          ),
        ),
        _PostJobTwoColumn(
          left: _PostJobPickerField(
            label: 'Job Start Date',
            value: startDateLabel,
            icon: Icons.calendar_today_outlined,
            onTap: onPickStartDate,
          ),
          right: _PostJobPickerField(
            label: 'Job End Date',
            value: endDateLabel,
            icon: Icons.calendar_today_outlined,
            onTap: onPickEndDate,
          ),
        ),
        _PostJobTwoColumn(
          left: _PostJobInput(
            label: 'Estimated Working Days',
            controller: workingDays,
            hint: 'e.g. 5',
            keyboardType: TextInputType.number,
          ),
          right: _PostJobDropdown(
            label: 'Search Radius',
            value: geographicBoundary,
            items: const ['1km', '2km', '5km', '10km', 'unlimited'],
            onChanged: onGeographicBoundaryChanged,
          ),
        ),
      ],
    );
  }
}

class _PostJobTwoColumn extends StatelessWidget {
  const _PostJobTwoColumn({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(children: [left, right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _PostJobInput extends StatelessWidget {
  const _PostJobInput({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.lines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int lines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return _PostJobLabeledField(
      label: label,
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 16,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: GawaGoColors.textFaint),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: lines > 1 ? 14 : 12,
          ),
          filled: true,
          fillColor: GawaGoColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
        ),
      ),
    );
  }
}

class _PostJobDropdown extends StatelessWidget {
  const _PostJobDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final String? hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PostJobLabeledField(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: GawaGoColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
        ),
        hint: hint == null ? null : Text(hint!),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _PostJobPickerField extends StatelessWidget {
  const _PostJobPickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PostJobLabeledField(
      label: label,
      child: Material(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GawaGoColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontSize: 16,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Icon(icon, size: 18, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostJobLabeledField extends StatelessWidget {
  const _PostJobLabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

class _PostJobMapPanel extends StatefulWidget {
  const _PostJobMapPanel({
    required this.pin,
    required this.profilePin,
    required this.onSetPin,
    required this.onLocate,
    this.focus,
  });

  final LatLng? pin;
  final LatLng? profilePin;
  final ValueChanged<LatLng> onSetPin;
  final VoidCallback onLocate;

  /// The chosen barangay's centre; the map moves there when it changes.
  final LatLng? focus;

  @override
  State<_PostJobMapPanel> createState() => _PostJobMapPanelState();
}

class _PostJobMapPanelState extends State<_PostJobMapPanel> {
  final MapController _controller = MapController();

  LatLng? get pin => widget.pin;
  LatLng? get profilePin => widget.profilePin;
  ValueChanged<LatLng> get onSetPin => widget.onSetPin;
  VoidCallback get onLocate => widget.onLocate;

  @override
  void didUpdateWidget(covariant _PostJobMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focus = widget.focus;
    if (widget.pin == null && focus != null && focus != oldWidget.focus) {
      _controller.move(focus, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 462,
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                // Fallback is Tayabas City (the service area), the same
                // center the worker screens use -- not the whole country,
                // where a tap can't place a usable pin.
                initialCenter:
                    pin ??
                    profilePin ??
                    widget.focus ??
                    const LatLng(14.0253, 121.5929),
                initialZoom: pin == null && profilePin == null ? 13 : 14,
                onTap: (_, point) => onSetPin(point),
              ),
              children: [
                if (shouldLoadMapTiles) _tiles(),
                if (pin != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pin!,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.deepOrange,
                          size: 38,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onLocate,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use My Current Location'),
              style: FilledButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: GawaGoColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tap the map to place a pin.')),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: GawaGoColors.ink,
                side: const BorderSide(color: GawaGoColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Pin on Map Manually'),
            ),
            if (profilePin != null)
              OutlinedButton.icon(
                onPressed: () => onSetPin(profilePin!),
                icon: const Icon(Icons.home_work_outlined, size: 18),
                label: const Text('Use Profile Pin'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: GawaGoColors.ink,
                  side: const BorderSide(color: GawaGoColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PostJobImagesBox extends StatelessWidget {
  const _PostJobImagesBox({
    required this.imagePaths,
    required this.onPickImages,
    required this.onRemove,
  });

  final List<String> imagePaths;
  final VoidCallback onPickImages;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reference Images',
          style: TextStyle(
            color: GawaGoColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: GawaGoColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GawaGoColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GawaGoColors.leafLine, width: 1.4),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Drag & drop images here',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text('or click to browse'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onPickImages,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GawaGoColors.ink,
                        side: const BorderSide(color: GawaGoColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Select Images'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose reference images from your phone.',
                  style: TextStyle(color: GawaGoColors.ink),
                ),
              ),
              if (imagePaths.isEmpty) ...[
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No reference images selected.'),
                ),
              ] else ...[
                const SizedBox(height: 10),
                ...imagePaths.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_outlined),
                    title: Text(
                      entry.value.split(RegExp(r'[/\\]')).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => onRemove(entry.key),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HouseholdMyReports extends StatelessWidget {
  const _HouseholdMyReports({required this.repository});

  final HouseholdRepository repository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HouseholdProfile>(
      future: repository.getProfile(),
      builder: (context, snapshot) {
        return MyComplaintsView(currentUsername: snapshot.data?.username);
      },
    );
  }
}

class _MyJobs extends StatefulWidget {
  const _MyJobs({
    required this.repository,
    required this.onChanged,
    required this.onPostNew,
  });

  final HouseholdRepository repository;
  final VoidCallback onChanged;
  final VoidCallback onPostNew;

  @override
  State<_MyJobs> createState() => _MyJobsState();
}

class _MyJobsState extends State<_MyJobs> {
  String _filter = 'all';
  late Future<(List<HouseholdJob>, List<GawaGoReview>)> _future = _load();

  Future<(List<HouseholdJob>, List<GawaGoReview>)> _load() async {
    final values = await Future.wait([
      widget.repository.getMyJobs(),
      widget.repository.getGivenReviews(),
    ]);
    return (values[0] as List<HouseholdJob>, values[1] as List<GawaGoReview>);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openJobDetail(int jobId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobDetail(
          repository: widget.repository,
          jobId: jobId,
          onChanged: widget.onChanged,
        ),
      ),
    );
    widget.onChanged();
    _reload();
  }

  Future<void> _rateWorker(HouseholdJob job) async {
    final worker = _workerToReview(job);
    if (worker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No worker is assigned to this job yet.')),
      );
      return;
    }
    final submitted = await showRateReviewDialog(
      context: context,
      workerName: worker.workerName,
      workerInitial: _initial(worker.workerName),
      workerVerified:
          worker.workerVerificationStatus.toLowerCase() == 'verified',
      onSubmit:
          ({
            required rating,
            required feedback,
            qualityOfWork,
            punctuality,
            communication,
            professionalism,
          }) => widget.repository.reviewWorker(
            job,
            worker,
            rating: rating,
            feedback: feedback,
            qualityOfWork: qualityOfWork,
            punctuality: punctuality,
            communication: communication,
            professionalism: professionalism,
          ),
    );
    if (submitted) {
      if (mounted) {
        await _offerSkillRatings(context, widget.repository, job, worker);
      }
      widget.onChanged();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Review submitted.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<HouseholdJob>, List<GawaGoReview>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final jobs = snapshot.data!.$1;
        final givenReviews = snapshot.data!.$2;
        // Mirrors web's historyHouseholdJobs (AppViews.jsx): the complete
        // record of every finished job, rated or not -- still-active jobs
        // live on the Dashboard instead.
        final historyJobs = jobs
            .where(
              (job) =>
                  _normalizedJobStatus(job.status) == 'completed' ||
                  _normalizedJobStatus(job.status) == 'cancelled',
            )
            .toList();
        final completedJobs = historyJobs
            .where((job) => _normalizedJobStatus(job.status) == 'completed')
            .toList();
        final cancelledJobs = historyJobs
            .where((job) => _normalizedJobStatus(job.status) == 'cancelled')
            .toList();
        final ratingsGiven = givenReviews
            .map((review) => review.rating)
            .whereType<double>()
            .toList();
        final avgRatingGiven = ratingsGiven.isEmpty
            ? null
            : ratingsGiven.reduce((a, b) => a + b) / ratingsGiven.length;
        final totalSpent = completedJobs.fold<double>(
          0,
          (sum, job) => sum + job.serviceRate,
        );
        final visible = switch (_filter) {
          'completed' => completedJobs,
          'cancelled' => cancelledJobs,
          _ => historyJobs,
        };

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              const Text(
                'My Jobs',
                style: TextStyle(
                  fontFamily: GawaGoColors.fontHeading,
                  color: GawaGoColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your complete job history — every completed and cancelled '
                'job in one place.',
                style: TextStyle(
                  color: GawaGoColors.textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              _HistoryStatCard(
                icon: Icons.check_circle_outline,
                iconColor: GawaGoColors.onPrimary,
                background: GawaGoColors.primary,
                value: '${completedJobs.length}',
                label: 'Jobs Completed',
              ),
              const SizedBox(height: 10),
              _HistoryStatCard(
                icon: Icons.attach_money_rounded,
                iconColor: GawaGoColors.cream,
                background: GawaGoColors.leafDeep,
                value: 'PHP ${totalSpent.toStringAsFixed(2)}',
                label: 'Total Spent',
              ),
              const SizedBox(height: 10),
              _HistoryStatCard(
                icon: Icons.star_rounded,
                iconColor: GawaGoColors.leafDeep,
                background: const Color(0x4D9EBF5E),
                value: avgRatingGiven == null
                    ? '—'
                    : avgRatingGiven.toStringAsFixed(1),
                label: 'Avg Rating Given',
              ),
              const SizedBox(height: 18),
              _MyJobsTabs(
                selected: _filter,
                allCount: historyJobs.length,
                completedCount: completedJobs.length,
                cancelledCount: cancelledJobs.length,
                onChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 14),
              if (historyJobs.isEmpty)
                _Card(
                  child: Column(
                    children: [
                      const Text(
                        'No finished jobs yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: GawaGoColors.fontHeading,
                          color: GawaGoColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Once a job is completed or cancelled, it will show '
                        'up here. Still-active jobs live on your Dashboard.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: widget.onPostNew,
                        icon: const Icon(Icons.post_add),
                        label: const Text('Post a New Job'),
                      ),
                    ],
                  ),
                )
              else if (visible.isEmpty)
                const _Card(
                  child: Text(
                    'Nothing matches this filter yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GawaGoColors.textMuted),
                  ),
                )
              else
                ...visible.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _HistoryJobCard(
                      job: job,
                      review: givenReviews
                          .where((review) => review.jobId == job.id)
                          .firstOrNull,
                      onRate: () => _rateWorker(job),
                      onViewDetails: () => _openJobDetail(job.id),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryStatCard extends StatelessWidget {
  const _HistoryStatCard({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GawaGoColors.line),
        boxShadow: gawagoCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: GawaGoColors.ink,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: GawaGoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyJobsTabs extends StatelessWidget {
  const _MyJobsTabs({
    required this.selected,
    required this.allCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.onChanged,
  });

  final String selected;
  final int allCount;
  final int completedCount;
  final int cancelledCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.start,
      children: [
        _MyJobsTabButton(
          label: 'All Jobs',
          count: allCount,
          value: 'all',
          selected: selected == 'all',
          onChanged: onChanged,
        ),
        _MyJobsTabButton(
          label: 'Completed',
          count: completedCount,
          value: 'completed',
          selected: selected == 'completed',
          onChanged: onChanged,
        ),
        _MyJobsTabButton(
          label: 'Cancelled',
          count: cancelledCount,
          value: 'cancelled',
          selected: selected == 'cancelled',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MyJobsTabButton extends StatelessWidget {
  const _MyJobsTabButton({
    required this.label,
    required this.count,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final int count;
  final String value;
  final bool selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: () => onChanged(value),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? GawaGoColors.ink : Colors.transparent,
          foregroundColor: selected
              ? GawaGoColors.cream
              : GawaGoColors.textMuted,
          side: BorderSide(
            color: selected ? GawaGoColors.ink : GawaGoColors.lineStrong,
            width: 1.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontFamily: GawaGoColors.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        child: Text('$label $count'),
      ),
    );
  }
}

/// One finished-job row on My Jobs -- mirrors web's .household-history-card
/// (AppViews.jsx / main.css): a status pill, either a "no worker was hired"
/// note (cancelled) or the assigned worker's avatar/name/rating/tags plus
/// the rate and, once given, the household's own star rating.
class _HistoryJobCard extends StatelessWidget {
  const _HistoryJobCard({
    required this.job,
    required this.review,
    required this.onRate,
    required this.onViewDetails,
  });

  final HouseholdJob job;
  final GawaGoReview? review;
  final VoidCallback onRate;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final isCancelled = _normalizedJobStatus(job.status) == 'cancelled';
    final assignedApp = _selectedWorker(job);
    final workerName = assignedApp?.workerName ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  job.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: GawaGoColors.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isCancelled
                      ? const Color(0xFFFBE2E2)
                      : GawaGoColors.leafTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText(job.statusLabel, job.status),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isCancelled
                        ? GawaGoColors.danger
                        : GawaGoColors.leafDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${job.jobType} · '
            '${job.locationLabel.trim().isEmpty ? "Location not set" : _barangay(job)}',
            style: const TextStyle(fontSize: 12, color: GawaGoColors.textMuted),
          ),
          if ((job.jobStartDate ?? '').isNotEmpty ||
              (job.jobEndDate ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            JobScheduleBox(
              startDate: job.jobStartDate,
              endDate: job.jobEndDate,
              workingDays: job.estimatedWorkingDays,
              finished: _normalizedJobStatus(job.status) == 'completed',
            ),
          ] else ...[
            const SizedBox(height: 2),
            Text(
              _jobScheduleDisplay(job),
              style: const TextStyle(
                fontSize: 12,
                color: GawaGoColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isCancelled)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: GawaGoColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 15,
                    color: GawaGoColors.textFaint,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No worker was hired',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: GawaGoColors.ink,
                        ),
                      ),
                      const Text(
                        'Job was cancelled before a worker was assigned.',
                        style: TextStyle(
                          fontSize: 12,
                          color: GawaGoColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: assignedApp != null
                      ? GawaGoColors.primary
                      : GawaGoColors.surfaceMuted,
                  child: Text(
                    assignedApp != null ? _initial(workerName) : '?',
                    style: TextStyle(
                      color: assignedApp != null
                          ? GawaGoColors.onPrimary
                          : GawaGoColors.textFaint,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              assignedApp != null
                                  ? workerName
                                  : 'Worker record unavailable',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: GawaGoColors.ink,
                              ),
                            ),
                          ),
                          if ((assignedApp?.workerVerificationStatus ?? '')
                                  .toLowerCase() ==
                              'verified') ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.check_circle,
                              size: 14,
                              color: GawaGoColors.leafDeep,
                            ),
                          ],
                        ],
                      ),
                      if (assignedApp != null)
                        Text(
                          assignedApp.workerRatingLabel,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: GawaGoColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _rateLabel(job),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: GawaGoColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (review != null) ...[
              Row(
                children: [
                  ...List.generate(5, (index) {
                    final starRating = (review!.rating ?? 0).round();
                    return Icon(
                      index < starRating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 16,
                      color: const Color(0xFFE0A82E),
                    );
                  }),
                  const SizedBox(width: 6),
                  Text(
                    '${(review!.rating ?? 0).toStringAsFixed(1)}/5',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: GawaGoColors.ink,
                    ),
                  ),
                ],
              ),
              if (review!.feedback.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"${review!.feedback}"',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: GawaGoColors.textMuted,
                  ),
                ),
              ],
            ] else if (job.canReview)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRate,
                  icon: const Icon(Icons.star_border_rounded, size: 16),
                  label: const Text('Rate Worker'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.ink,
                    side: const BorderSide(color: GawaGoColors.ink, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: onViewDetails,
                style: TextButton.styleFrom(
                  foregroundColor: GawaGoColors.leafDeep,
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text('View Details'),
              ),
          ],
        ],
      ),
    );
  }
}

class _JobDetail extends StatefulWidget {
  const _JobDetail({
    required this.repository,
    required this.jobId,
    required this.onChanged,
  });

  final HouseholdRepository repository;
  final int jobId;
  final VoidCallback onChanged;

  @override
  State<_JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<_JobDetail> {
  late Future<HouseholdJob> _future = widget.repository.getJob(widget.jobId);
  bool _busy = false;

  void _reload() => setState(() {
    _future = widget.repository.getJob(widget.jobId);
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      _reload();
      if (mounted) _message('Action completed.');
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedDetailScaffold(
      title: 'Job Details',
      child: FutureBuilder<HouseholdJob>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorState(error: snapshot.error, onRetry: _reload);
          }
          if (!snapshot.hasData) return const AppLoadingState();
          final job = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _JobDetailsSummaryCard(
                job: job,
                busy: _busy,
                // Editable until someone is hired; the empty matches screen
                // tells households to widen the radius here.
                onEdit: job.status == 'open'
                    ? () async {
                        final changes = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => _EditJobDialog(job: job),
                        );
                        if (changes == null || changes.isEmpty) return;
                        await _run(
                          () => widget.repository.updateJob(job.id, changes),
                        );
                      }
                    : null,
                onCancel: job.status == 'open' || job.status == 'assigned'
                    ? () async {
                        final confirmed = await _confirmDialog(
                          context,
                          title: 'Cancel this job?',
                          message: "This can't be undone.",
                          destructive: true,
                        );
                        if (!confirmed) return;
                        await _run(
                          () => widget.repository.updateJobStatus(
                            job.id,
                            'cancelled',
                          ),
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 26),
              _CompletionReviewPanel(
                job: job,
                busy: _busy,
                // The household marks a job done (AGENTS.md I.A); the backend
                // decides when (a hired worker, a verified household, the
                // start date reached) through can_mark_done.
                onMarkDone: job.canMarkDone
                    ? () async {
                        final confirmed = await _confirmDialog(
                          context,
                          title: 'Mark this job as done?',
                          message:
                              "The worker will be notified and you can both "
                              "leave a review. This can't be undone.",
                        );
                        if (!confirmed) return;
                        await _run(
                          () => widget.repository.updateJobStatus(
                            job.id,
                            'completed',
                          ),
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 26),
              _ApplicantsPanel(
                job: job,
                repository: widget.repository,
                onChanged: _reload,
                onOpenApplicant: (application) async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ApplicantDetail(
                        job: job,
                        application: application,
                        repository: widget.repository,
                        onChanged: _reload,
                      ),
                    ),
                  );
                  _reload();
                },
              ),
              const SizedBox(height: 26),
              _SmartMatchedWorkersPanel(
                job: job,
                repository: widget.repository,
                onChanged: _reload,
              ),
              const SizedBox(height: 26),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    final submitted = await showReportIssueDialog(
                      context: context,
                      jobId: job.id,
                      jobTitle: job.title,
                      isHousehold: true,
                      applicants: job.applications
                          .map(
                            (application) => ReportApplicantOption(
                              workerId: application.workerId,
                              label: application.workerName.isEmpty
                                  ? application.workerUsername
                                  : application.workerName,
                            ),
                          )
                          .toList(),
                    );
                    if (submitted && context.mounted) {
                      _message(
                        'Complaint submitted. Our admin team will review it.',
                      );
                    }
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('File a Complaint'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Edits an open job's wording, rate, dates, worker count and search
/// radius. Pops with only the fields that changed (an unchanged past start
/// date would otherwise be refused as a past date), or null on cancel.
class _EditJobDialog extends StatefulWidget {
  const _EditJobDialog({required this.job});

  final HouseholdJob job;

  @override
  State<_EditJobDialog> createState() => _EditJobDialogState();
}

class _EditJobDialogState extends State<_EditJobDialog> {
  static const _radii = ['1km', '2km', '5km', '10km', 'unlimited'];
  static const _rateTypes = ['Per Day', 'Per Hour', 'Fixed Rate'];

  late final _title = TextEditingController(text: widget.job.title);
  late final _description = TextEditingController(text: widget.job.description);
  late final _rate = TextEditingController(
    text: widget.job.serviceRate.toStringAsFixed(2),
  );
  late final _slots = TextEditingController(text: '${widget.job.workerSlots}');
  late final _workingDays = TextEditingController(
    text: widget.job.estimatedWorkingDays?.toString() ?? '',
  );
  late String _rateType = _rateTypes.contains(widget.job.rateTypeLabel)
      ? widget.job.rateTypeLabel
      : 'Per Day';
  late String _radius = _radii.contains(widget.job.geographicBoundary)
      ? widget.job.geographicBoundary
      : '1km';
  late DateTime? _start = DateTime.tryParse(widget.job.jobStartDate ?? '');
  late DateTime? _end = DateTime.tryParse(widget.job.jobEndDate ?? '');
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _rate.dispose();
    _slots.dispose();
    _workingDays.dispose();
    super.dispose();
  }

  String _iso(DateTime? date) => date == null
      ? ''
      : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _rateTypeValue(String label) => switch (label) {
    'Per Hour' => 'per_hour',
    'Fixed Rate' => 'fixed',
    _ => 'per_day',
  };

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = start ? _start : _end;
    final first = start ? today : (_start ?? today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(first)
          ? current
          : first,
      firstDate: first,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _error = null;
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = null;
      } else {
        _end = picked;
      }
    });
  }

  void _save() {
    final job = widget.job;
    final rate = double.tryParse(_rate.text.trim());
    final slots = int.tryParse(_slots.text.trim());
    final daysText = _workingDays.text.trim();
    final days = daysText.isEmpty ? null : int.tryParse(daysText);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the job a title.');
      return;
    }
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Enter an offered rate above zero.');
      return;
    }
    if (slots == null || slots < 1 || slots > 50) {
      setState(() => _error = 'Workers needed must be between 1 and 50.');
      return;
    }
    if (daysText.isNotEmpty && (days == null || days < 1 || days > 366)) {
      setState(
        () => _error = 'Working days must be a number between 1 and 366.',
      );
      return;
    }
    if (_start == null) {
      setState(() => _error = 'A job needs a start date.');
      return;
    }
    final changes = <String, dynamic>{};
    if (_title.text.trim() != job.title) changes['title'] = _title.text.trim();
    if (_description.text.trim() != job.description) {
      changes['description'] = _description.text.trim();
    }
    if ((rate - job.serviceRate).abs() > 0.001) {
      changes['service_rate'] = rate.toStringAsFixed(2);
    }
    if (_rateTypeValue(_rateType) != _rateTypeValue(job.rateTypeLabel)) {
      changes['rate_type'] = _rateTypeValue(_rateType);
    }
    if (slots != job.workerSlots) changes['worker_slots'] = slots;
    if (days != job.estimatedWorkingDays) {
      changes['estimated_working_days'] = days;
    }
    if (_iso(_start) != (job.jobStartDate ?? '')) {
      changes['job_start_date'] = _iso(_start);
    }
    if (_iso(_end) != (job.jobEndDate ?? '')) {
      changes['job_end_date'] = _end == null ? null : _iso(_end);
    }
    if (_radius != job.geographicBoundary) {
      changes['geographic_boundary'] = _radius;
    }
    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit job'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Job title'),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Offered rate (PHP)',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _rateType,
              decoration: const InputDecoration(labelText: 'Rate type'),
              items: _rateTypes
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _rateType = value ?? _rateType),
            ),
            TextField(
              controller: _slots,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Workers needed'),
            ),
            TextField(
              controller: _workingDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Working days (optional)',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start date'),
              trailing: Text(_start == null ? 'Pick' : _iso(_start)),
              onTap: () => _pickDate(start: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('End date (optional)'),
              trailing: Text(_end == null ? 'None' : _iso(_end)),
              onTap: () => _pickDate(start: false),
            ),
            DropdownButtonFormField<String>(
              key: const ValueKey('edit-job-radius'),
              initialValue: _radius,
              decoration: const InputDecoration(labelText: 'Search radius'),
              items: _radii
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _radius = value ?? _radius),
            ),
            const SizedBox(height: 8),
            const Text(
              "The job site can't be moved after posting.",
              style: TextStyle(fontSize: 12, color: GawaGoColors.textMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: GawaGoColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save changes')),
      ],
    );
  }
}

class _JobDetailsSummaryCard extends StatelessWidget {
  const _JobDetailsSummaryCard({
    required this.job,
    required this.busy,
    required this.onCancel,
    this.onEdit,
  });

  final HouseholdJob job;
  final bool busy;
  final VoidCallback? onCancel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: GawaGoColors.fontHeading,
                  color: GawaGoColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              _JobStatusPill(status: job.status),
            ],
          ),
          const SizedBox(height: 16),
          _LargeDetailBox(label: 'Service Type', value: job.jobType),
          _LargeDetailBox(label: 'Location', value: _barangay(job)),
          _LargeDetailBox(label: 'Offered Rate', value: _rateLabel(job)),
          _LargeDetailBox(label: 'Schedule', value: _jobScheduleDisplay(job)),
          if (job.jobStartDate != null || job.jobEndDate != null)
            _LargeDetailBox(
              label: 'Job Period',
              value:
                  '${formatJobDate(job.jobStartDate)} to ${formatJobDate(job.jobEndDate)}',
            ),
          if (job.estimatedWorkingDays != null)
            _LargeDetailBox(
              label: 'Estimated Working Days',
              value: '${job.estimatedWorkingDays}',
            ),
          _LargeDetailBox(
            label: 'Search Radius',
            value: job.geographicBoundary,
          ),
          _LargeDetailBox(
            label: 'Workers Needed',
            value: '${job.workerSlots} worker(s)',
          ),
          _LargeDetailBox(
            label: 'Hiring Status',
            value: '${job.hiredCount}/${job.workerSlots} Hired',
          ),
          if (onEdit != null) ...[
            OutlinedButton.icon(
              key: const ValueKey('household-edit-job'),
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Job'),
            ),
            const SizedBox(height: 10),
          ],
          if (onCancel != null)
            OutlinedButton(
              onPressed: busy ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF2E45),
                side: const BorderSide(color: Color(0xFFFF2E45)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontFamily: GawaGoColors.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              child: const Text('Cancel Job'),
            ),
        ],
      ),
    );
  }
}

/// After a review is saved, offers the optional per-skill ratings the web
/// shows. A failure to load the worker's skills is not worth interrupting the
/// flow for -- the review itself is already in -- so it just skips.
Future<void> _offerSkillRatings(
  BuildContext context,
  HouseholdRepository repository,
  HouseholdJob job,
  HouseholdApplication application,
) async {
  final List<RatableSkill> skills;
  // The job's own skill is always rateable, even if the worker never listed
  // it -- otherwise the household can't rate the very work it hired them for
  // (the web client offers it too). It has no portfolio id yet, so it rides
  // on a placeholder id and is sent by name.
  const unlistedJobSkillId = -1;
  final unlistedSkillNames = <int, String>{};
  try {
    final portfolio = await repository.getWorkerPortfolio(application.workerId);
    skills = [
      for (final skill in portfolio.skills)
        RatableSkill(id: skill.id, name: skill.skillName),
    ];
    final jobSkill = job.requiredSkill.trim();
    final listed = skills.any(
      (skill) => skill.name.toLowerCase() == jobSkill.toLowerCase(),
    );
    if (jobSkill.isNotEmpty && !listed) {
      skills.add(RatableSkill(id: unlistedJobSkillId, name: jobSkill));
      unlistedSkillNames[unlistedJobSkillId] = jobSkill;
    }
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final saved = await showRateSkillsDialog(
    context: context,
    workerName: application.workerName,
    skills: skills,
    onSubmit: (ratings) => repository.rateSkills(
      job,
      ratings,
      workerId: application.workerId,
      unlistedSkillNames: unlistedSkillNames,
    ),
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Skill ratings saved.')));
  }
}

class _CompletionReviewPanel extends StatelessWidget {
  const _CompletionReviewPanel({
    required this.job,
    required this.busy,
    required this.onMarkDone,
  });

  final HouseholdJob job;
  final bool busy;
  final VoidCallback? onMarkDone;

  @override
  Widget build(BuildContext context) {
    final worker = _selectedWorker(job);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: GawaGoColors.line)),
            ),
            child: Text(
              'Completion & Review',
              style: gawagoHeading(fontSize: 18),
            ),
          ),
          const SizedBox(height: 14),
          _ServiceReviewCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: GawaGoColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const _SmallLabel('Worker'),
                Text(
                  worker?.workerName ?? 'No worker selected',
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 15,
                    height: 1.4,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const _SmallLabel('Status'),
                Text(
                  statusText(job.statusLabel, job.status),
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 15,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (worker == null)
            _WarningBox(
              message:
                  'No worker is assigned yet, so completion controls are not available.',
            )
          else if (job.markDoneNote.isNotEmpty)
            _WarningBox(message: job.markDoneNote),
          const SizedBox(height: 14),
          const Divider(color: GawaGoColors.border),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : onMarkDone,
            style: FilledButton.styleFrom(
              backgroundColor: onMarkDone == null
                  ? GawaGoColors.textFaint
                  : GawaGoColors.primary,
              foregroundColor: GawaGoColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontFamily: GawaGoColors.fontBody,
                fontSize: 14,
                letterSpacing: 0,
              ),
            ),
            child: Text(busy ? 'Saving...' : 'Mark as done'),
          ),
        ],
      ),
    );
  }
}

class _ApplicantsPanel extends StatelessWidget {
  const _ApplicantsPanel({
    required this.job,
    required this.repository,
    required this.onOpenApplicant,
    required this.onChanged,
  });

  final HouseholdJob job;
  final HouseholdRepository repository;
  final ValueChanged<HouseholdApplication> onOpenApplicant;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final applicants = _visibleApplicants(job);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Applicants',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Workers who submitted an application for this job.',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          if (applicants.isEmpty)
            const _DashedEmptyBox(message: 'No worker applications yet.')
          else
            ...applicants.map(
              (application) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildApplicantCard(
                  context: context,
                  job: job,
                  repository: repository,
                  application: application,
                  topMatchId: _topApplicantId(applicants),
                  onOpenApplicant: onOpenApplicant,
                  onChanged: onChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "Applicants" modal the dashboard opens: every worker waiting on a
/// response for one job, with the three responses on each card.
Future<void> showApplicantsDialog({
  required BuildContext context,
  required HouseholdJob job,
  required HouseholdRepository repository,
  required ValueChanged<HouseholdApplication> onOpenApplicant,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final applicants = _visibleApplicants(job);
      final topMatchId = _topApplicantId(applicants);
      return Dialog(
        backgroundColor: GawaGoColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
              color: GawaGoColors.deepGreen,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'APPLICANTS',
                          style: TextStyle(
                            color: GawaGoColors.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: GawaGoColors.fontHeading,
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${applicants.length} applicant'
                          '${applicants.length == 1 ? '' : 's'} waiting · '
                          'review and respond below',
                          style: const TextStyle(
                            color: GawaGoColors.mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (applicants.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                color: GawaGoColors.cream,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: applicants
                      .map(
                        (application) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WorkerPhoto(
                              photoUrl: application.workerProfilePhotoUrl,
                              name: application.workerName,
                              size: 26,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              application.workerName.split(' ').first,
                              style: const TextStyle(
                                color: GawaGoColors.textMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            Flexible(
              child: applicants.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No workers have applied to this job yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: GawaGoColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(14),
                      itemCount: applicants.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildApplicantCard(
                        context: context,
                        job: job,
                        repository: repository,
                        application: applicants[index],
                        topMatchId: topMatchId,
                        onOpenApplicant: (application) {
                          Navigator.of(context).pop();
                          onOpenApplicant(application);
                        },
                        onChanged: () {
                          Navigator.of(context).pop();
                          onChanged();
                        },
                      ),
                    ),
            ),
            const Divider(height: 1, color: GawaGoColors.border),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: GawaGoColors.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}

/// Rejected/closed applications are history, not something the household
/// still has to respond to, so the applicant lists leave them out.
List<HouseholdApplication> _visibleApplicants(HouseholdJob job) => job
    .applications
    .where(
      (application) =>
          application.status.toLowerCase() != 'rejected' &&
          application.status.toLowerCase() != 'closed',
    )
    .toList();

/// Only badge a "Top match" when there is something to compare against.
int? _topApplicantId(List<HouseholdApplication> applicants) {
  final scored = applicants
      .where((application) => (application.workerMatchScore ?? 0) > 0)
      .toList();
  if (scored.length < 2) return null;
  scored.sort(
    (a, b) => (b.workerMatchScore ?? 0).compareTo(a.workerMatchScore ?? 0),
  );
  return scored.first.id;
}

Widget _buildApplicantCard({
  required BuildContext context,
  required HouseholdJob job,
  required HouseholdRepository repository,
  required HouseholdApplication application,
  required int? topMatchId,
  required ValueChanged<HouseholdApplication> onOpenApplicant,
  required VoidCallback onChanged,
}) {
  final status = application.status.trim().toLowerCase();
  final settled =
      status == 'hired' || status == 'completed' || status == 'hire_requested';

  Future<void> respond(String next) async {
    try {
      await repository.setApplicationStatus(application.id, next);
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next == 'rejected'
                  ? 'Application declined.'
                  : '${application.workerName} is hired. The job is now in progress.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  return ApplicantCard(
    name: application.workerName,
    locationLabel: application.locationLabel,
    photoUrl: application.workerProfilePhotoUrl,
    verified: application.workerVerificationStatus.toLowerCase() == 'verified',
    matchScore: application.workerMatchScore,
    ratingLabel: application.workerRatingLabel,
    ratingCount: application.workerRatingCount,
    rateLabel: _shortRate(application.workerRateLabel),
    completedJobs: application.workerCompletedJobs,
    skills: application.workerSkills,
    bio: application.workerBio,
    appliedAgo: formatTimeAgo(application.appliedAt),
    isTopMatch: topMatchId != null && topMatchId == application.id,
    statusLabel: settled
        ? (application.statusLabel.isNotEmpty
              ? application.statusLabel
              : applicationStatusLabel(application.status))
        : null,
    onDecline: () async {
      final confirmed = await _confirmDialog(
        context,
        title: 'Decline this application?',
        message: "This can't be undone.",
        destructive: true,
      );
      if (confirmed) await respond('rejected');
    },
    onViewProfile: () => onOpenApplicant(application),
    // Applying is consent, so accepting an applicant hires them outright,
    // as on the website; only invited workers get a request to confirm.
    onAccept: () async {
      final confirmed = await _confirmDialog(
        context,
        title: 'Accept ${application.workerName}?',
        message: 'They will be hired and the job moves to In progress.',
      );
      if (confirmed) await respond('hired');
    },
  );
}

class _SmartMatchedWorkersPanel extends StatelessWidget {
  const _SmartMatchedWorkersPanel({
    required this.job,
    required this.repository,
    required this.onChanged,
  });

  final HouseholdJob job;
  final HouseholdRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Matched Workers',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Suggested workers ranked by skill, verification status, distance, ratings, and service rate.',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<RecommendedWorker>>(
            future: repository.getRecommendedWorkers(job.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(
                  error: snapshot.error,
                  onRetry: () => (context as Element).markNeedsBuild(),
                );
              }
              if (!snapshot.hasData) return const AppLoadingState();
              final workers = snapshot.data!;
              if (workers.isEmpty) {
                return const _DashedEmptyBox(
                  message:
                      'No recommended workers are available yet. Check again after workers add skills, verification, or location details.',
                );
              }
              return Column(
                children: workers
                    .map(
                      (worker) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: WorkerMatchCard(
                          name: worker.displayName,
                          locationLabel: worker.locationLabel,
                          photoUrl: worker.profilePhotoUrl,
                          verified:
                              worker.verificationStatus.toLowerCase() ==
                              'verified',
                          matchScore: worker.aiScore,
                          ratingLabel: worker.ratingLabel,
                          ratingCount: worker.ratingCount,
                          distanceLabel: worker.distanceLabel,
                          completedJobs: worker.completedJobs,
                          rateLabel: _shortRate(worker.workerRate),
                          skills: worker.skills,
                          bio: worker.bio,
                          // Smart Matching order; it has no AI score.
                          showScore: false,
                          requestSent:
                              _applicationForWorker(
                                job,
                                worker,
                              )?.status.toLowerCase() ==
                              'hire_requested',
                          onViewProfile: () => _showWorkerMatchProfile(
                            context,
                            repository: repository,
                            job: job,
                            worker: worker,
                            onChanged: onChanged,
                          ),
                          onSendRequest: () => _hireRecommendedWorker(
                            context: context,
                            repository: repository,
                            job: job,
                            worker: worker,
                            onChanged: onChanged,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: child,
    );
  }
}

class _LargeDetailBox extends StatelessWidget {
  const _LargeDetailBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallLabel(label),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(
        color: GawaGoColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFC04D)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF8A5B00),
          fontSize: 13,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DashedEmptyBox extends StatelessWidget {
  const _DashedEmptyBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: GawaGoColors.textMuted,
          fontSize: 14,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// A match card's "View Profile" opens the same household-facing profile an
/// applicant gets, so a worker looks the same however the household reached
/// them.
Future<void> _showWorkerMatchProfile(
  BuildContext context, {
  required HouseholdRepository repository,
  required HouseholdJob job,
  required RecommendedWorker worker,
  required VoidCallback onChanged,
}) {
  final requested = _applicationForWorker(
    job,
    worker,
  )?.status.trim().toLowerCase();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _WorkerProfileScreen(
        subject: _WorkerProfileSubject.fromRecommendation(worker),
        repository: repository,
        hireEnabled: requested != 'hired' && requested != 'hire_requested',
        hireLabel: requested == 'hired'
            ? 'Hired'
            : requested == 'hire_requested'
            ? 'Request Sent'
            : null,
        matchBreakdown: AiMatchBreakdown(
          skillSharePercent: worker.skillSharePercent,
          exactSkillMatch: worker.exactSkillMatch,
        ),
        onHire: () => _hireRecommendedWorker(
          context: context,
          repository: repository,
          job: job,
          worker: worker,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

class _CompactProfileFact extends StatelessWidget {
  const _CompactProfileFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Not available' : value,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 15,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicantFeedbackItem extends StatelessWidget {
  const _ApplicantFeedbackItem({required this.review});

  final GawaGoReview review;

  @override
  Widget build(BuildContext context) {
    final rating = review.rating == null
        ? ''
        : '${review.rating!.toStringAsFixed(1)} / 5';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rating.isNotEmpty)
            Text(
              rating,
              style: const TextStyle(
                color: GawaGoColors.leafDeep,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (review.feedback.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              review.feedback,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (review.jobTitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              review.jobTitle,
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceReviewCard extends StatelessWidget {
  const _ServiceReviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: child,
    );
  }
}

class _ApplicantDetail extends StatefulWidget {
  const _ApplicantDetail({
    required this.job,
    required this.application,
    required this.repository,
    required this.onChanged,
  });

  final HouseholdJob job;
  final HouseholdApplication application;
  final HouseholdRepository repository;
  final VoidCallback onChanged;

  @override
  State<_ApplicantDetail> createState() => _ApplicantDetailState();
}

class _ApplicantDetailState extends State<_ApplicantDetail> {
  bool _busy = false;

  HouseholdJob get job => widget.job;
  HouseholdApplication get application => widget.application;
  HouseholdRepository get repository => widget.repository;

  Future<void> _action(BuildContext context, String status) async {
    if (_busy) return;
    final isHire = status == 'hired';
    final confirmed = await _confirmDialog(
      context,
      title: isHire ? 'Hire this worker?' : 'Reject this application?',
      message: isHire
          ? '${application.workerName.isEmpty ? application.workerUsername : application.workerName} will be hired for this job.'
          : "This can't be undone.",
      destructive: !isHire,
    );
    if (!confirmed || !context.mounted) return;
    setState(() => _busy = true);
    try {
      await repository.setApplicationStatus(application.id, status);
      widget.onChanged();
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(BuildContext context) async {
    final submitted = await showRateReviewDialog(
      context: context,
      workerName: application.workerName,
      workerInitial: _initial(application.workerName),
      workerVerified:
          application.workerVerificationStatus.toLowerCase() == 'verified',
      onSubmit:
          ({
            required rating,
            required feedback,
            qualityOfWork,
            punctuality,
            communication,
            professionalism,
          }) => repository.reviewWorker(
            job,
            application,
            rating: rating,
            feedback: feedback,
            qualityOfWork: qualityOfWork,
            punctuality: punctuality,
            communication: communication,
            professionalism: professionalism,
          ),
    );
    if (submitted) {
      if (context.mounted) {
        await _offerSkillRatings(context, repository, job, application);
      }
      widget.onChanged();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (application.status == 'pending')
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _action(context, 'rejected'),
          icon: const Icon(Icons.close),
          label: const Text('Reject'),
        ),
      if (job.status == 'completed' &&
          application.status == 'completed' &&
          application.householdCanReview)
        FilledButton.icon(
          onPressed: () => _review(context),
          icon: const Icon(Icons.star_outline),
          label: const Text('Review Worker'),
        ),
    ];
    return _WorkerProfileScreen(
      subject: _WorkerProfileSubject.fromApplication(application),
      repository: repository,
      hireEnabled: application.status == 'pending' && !_busy,
      hireLabel: application.status == 'pending'
          ? null
          : (application.statusLabel.isNotEmpty
                ? application.statusLabel
                : applicationStatusLabel(application.status)),
      onHire: () => _action(context, 'hired'),
      bottomActions: actions,
      // Coordinates arrive for any applicant now, so this fallback only
      // means the worker never pinned a location on their profile.
      mapPanel:
          application.workerLatitude == null ||
              application.workerLongitude == null
          ? _WorkerLocationPrivatePanel(
              distanceLabel: application.distanceLabel,
            )
          : LocationRouteMap(
              start: LatLng(
                application.workerLatitude!,
                application.workerLongitude!,
              ),
              end: LatLng(job.latitude, job.longitude),
              startLabel: 'Worker',
              endLabel: 'Job',
              routePoints: application.routePoints
                  .map((point) => LatLng(point.latitude, point.longitude))
                  .toList(),
              roadDistanceKm: application.distanceKm,
            ),
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile({required this.repository, required this.onSaved});

  final HouseholdRepository repository;
  final VoidCallback onSaved;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        widget.repository.getProfile(),
        widget.repository.getReceivedReviews(),
        widget.repository.getGivenReviews(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () => (context as Element).markNeedsBuild(),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final profile = snapshot.data![0] as HouseholdProfile;
        final received = snapshot.data![1] as List<GawaGoReview>;
        final given = snapshot.data![2] as List<GawaGoReview>;
        return _ProfileForm(
          profile: profile,
          receivedReviews: received,
          givenReviews: given,
          repository: widget.repository,
          onSaved: () {
            widget.onSaved();
            setState(() {});
          },
        );
      },
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({
    required this.profile,
    required this.receivedReviews,
    required this.givenReviews,
    required this.repository,
    required this.onSaved,
  });

  final HouseholdProfile profile;
  final List<GawaGoReview> receivedReviews;
  final List<GawaGoReview> givenReviews;
  final HouseholdRepository repository;
  final VoidCallback onSaved;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final _first = TextEditingController(text: widget.profile.firstName);
  late final _last = TextEditingController(text: widget.profile.lastName);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _username = TextEditingController(text: widget.profile.username);
  late final _street = TextEditingController(
    text: _streetFromLocation(widget.profile.locationLabel),
  );
  late String? _barangay = _barangayFromText(widget.profile.locationLabel);
  // Mutable, and with a map picker below to set it: this used to be
  // `late final`, computed once from the profile's (possibly null -- web
  // registration can save a label with no coordinates, see P-07)
  // lat/lng and never settable afterward, so a household with no pin
  // saved was told "select your location" with no way to do it (F-12).
  late LatLng? _profilePin =
      widget.profile.latitude == null || widget.profile.longitude == null
      ? null
      : LatLng(widget.profile.latitude!, widget.profile.longitude!);
  String? _photoPath;
  bool _saving = false;

  Future<void> _locateProfilePin() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied.');
      }
      final value = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _profilePin = LatLng(value.latitude, value.longitude));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  Future<void> _pickPhoto() async {
    const group = XTypeGroup(
      label: 'Profile photo',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    setState(() => _photoPath = file.path);
  }

  Future<void> _save() async {
    if (_saving) return;
    final pin = _profilePin;
    if (pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select your exact Tayabas location on the map.'),
        ),
      );
      return;
    }
    if (_barangay == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select your barangay.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'email': _email.text.trim(),
        'phone': sanitizePhilippinesPhone(_phone.text),
        'location_label': [
          _barangay!,
          _street.text.trim(),
        ].where((part) => part.trim().isNotEmpty).join(', '),
        'latitude': _coordinateForApi(pin.latitude),
        'longitude': _coordinateForApi(pin.longitude),
      }, profilePhotoPath: _photoPath);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latestReceived = widget.receivedReviews.take(1).toList();
    final latestGiven = widget.givenReviews.take(1).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        const Text(
          'My Profile Household',
          style: TextStyle(
            fontFamily: GawaGoColors.fontHeading,
            color: GawaGoColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        _ProfilePanel(
          title: 'My Profile',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    _ProfileAvatar(
                      profile: widget.profile,
                      localPhotoPath: _photoPath,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.profile.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        color: GawaGoColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${widget.profile.username}',
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        const _ProfileChip(label: 'Household'),
                        _ProfileChip(
                          label: formatStatus(
                            widget.profile.verificationStatus,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _ProfileInfoLine(label: 'Account Type', value: 'Household'),
              _ProfileInfoLine(
                label: 'Barangay',
                value: _barangay ?? _profileBarangay(widget.profile),
              ),
              _ProfileInfoLine(
                label: 'Phone Number',
                value: widget.profile.phone.isEmpty
                    ? 'Not set'
                    : widget.profile.phone,
              ),
              _ProfileInfoLine(
                label: 'Email',
                value: widget.profile.email.isEmpty
                    ? 'Not set'
                    : widget.profile.email,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ProfilePanel(
          title: 'Edit Profile Information',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Profile Photo',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _FileChooserRow(
                filename: _photoPath == null
                    ? 'No file chosen'
                    : _photoPath!.split(RegExp(r'[/\\]')).last,
                onChoose: _pickPhoto,
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose a clear photo from your phone.',
                style: TextStyle(color: GawaGoColors.ink, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _ProfileTextField(label: 'First Name', controller: _first),
              _ProfileTextField(label: 'Last Name', controller: _last),
              _ProfileTextField(
                label: 'Username',
                controller: _username,
                enabled: false,
              ),
              _ProfileTextField(label: 'Email', controller: _email),
              _ProfileTextField(label: 'Phone Number', controller: _phone),
              _ProfileDropdownField(
                label: 'Barangay',
                value: _barangay,
                hint: '---Select Barangay---',
                items: gawagoBarangays,
                onChanged: (value) => setState(() => _barangay = value),
              ),
              _ProfileTextField(
                label: 'Street / House No.',
                controller: _street,
                hint: 'QZ, Philippines',
              ),
              const SizedBox(height: 14),
              const Text(
                'Exact Household Location',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 7),
              _PostJobMapPanel(
                pin: _profilePin,
                profilePin: null,
                onSetPin: (point) => setState(() => _profilePin = point),
                onLocate: _locateProfilePin,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: GawaGoColors.primary,
                    foregroundColor: GawaGoColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: GawaGoColors.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  child: Text(_saving ? 'Saving...' : 'Edit Profile'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Feedback & Rating',
          style: TextStyle(
            fontFamily: GawaGoColors.fontHeading,
            color: GawaGoColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        _ReviewsPanel(
          title: 'Feedback from Workers',
          reviews: latestReceived,
          emptyMessage: 'No feedback from workers yet.',
        ),
        const SizedBox(height: 18),
        _ReviewsPanel(
          title: 'Reviews You Submitted',
          reviews: latestGiven,
          emptyMessage: 'No submitted reviews yet.',
        ),
      ],
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GawaGoColors.line),
        boxShadow: gawagoCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: GawaGoColors.line)),
            ),
            child: Text(title, style: gawagoHeading(fontSize: 17)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.localPhotoPath});

  final HouseholdProfile profile;
  final String? localPhotoPath;

  @override
  Widget build(BuildContext context) {
    final initial = _initial(profile.fullName);
    ImageProvider? image;
    if (localPhotoPath != null) {
      image = FileImage(File(localPhotoPath!));
    } else if (profile.profilePhotoUrl.isNotEmpty) {
      image = NetworkImage(profile.profilePhotoUrl);
    }
    return CircleAvatar(
      radius: 68,
      backgroundColor: GawaGoColors.surfaceMuted,
      backgroundImage: image,
      child: image == null
          ? Text(
              initial,
              style: const TextStyle(
                fontFamily: GawaGoColors.fontHeading,
                color: GawaGoColors.leafDeep,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: GawaGoColors.leafTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GawaGoColors.leafLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.leafDeep,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ProfileInfoLine extends StatelessWidget {
  const _ProfileInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontSize: 14,
            height: 1.25,
            letterSpacing: 0,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: value.isEmpty ? 'Not set' : value),
          ],
        ),
      ),
    );
  }
}

class _FileChooserRow extends StatelessWidget {
  const _FileChooserRow({required this.filename, required this.onChoose});

  final String filename;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          TextButton(
            onPressed: onChoose,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF2F2F2),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(
                fontFamily: GawaGoColors.fontBody,
                fontSize: 14,
                letterSpacing: 0,
              ),
            ),
            child: const Text('Choose File'),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 14,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _ProfileFieldShell(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 14,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: GawaGoColors.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
        ),
      ),
    );
  }
}

class _ProfileDropdownField extends StatelessWidget {
  const _ProfileDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final String? hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ProfileFieldShell(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: GawaGoColors.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
        ),
        hint: hint == null ? null : Text(hint!),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _ProfileFieldShell extends StatelessWidget {
  const _ProfileFieldShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ReviewsPanel extends StatelessWidget {
  const _ReviewsPanel({
    required this.title,
    required this.reviews,
    required this.emptyMessage,
  });

  final String title;
  final List<GawaGoReview> reviews;
  final String emptyMessage;

  void _showAll(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: GawaGoColors.fontHeading,
                color: GawaGoColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            if (reviews.isEmpty)
              _DashedEmptyBox(message: emptyMessage)
            else
              ...reviews.map(_ReviewPreviewCard.new),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ProfilePanel(
      title: title,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => _showAll(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: GawaGoColors.leafDeep,
                backgroundColor: Colors.transparent,
                side: const BorderSide(
                  color: GawaGoColors.lineStrong,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontFamily: GawaGoColors.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('View All'),
            ),
          ),
          const SizedBox(height: 8),
          if (reviews.isEmpty)
            _DashedEmptyBox(message: emptyMessage)
          else
            ...reviews.map(_ReviewPreviewCard.new),
        ],
      ),
    );
  }
}

class _ReviewPreviewCard extends StatelessWidget {
  const _ReviewPreviewCard(this.review);

  final GawaGoReview review;

  @override
  Widget build(BuildContext context) {
    final name = review.authorName.isNotEmpty
        ? review.authorName
        : review.targetName;
    final rating = review.rating == null
        ? 'No rating'
        : '${review.rating!.toStringAsFixed(1)}/5';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: GawaGoColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                rating,
                style: const TextStyle(
                  fontFamily: GawaGoColors.fontHeading,
                  color: GawaGoColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            review.feedback.isEmpty ? 'No written feedback.' : review.feedback,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 18,
              height: 1.3,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formatLocalDateTime(review.createdAt, fallback: review.displayDate),
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 17,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Verification extends StatefulWidget {
  const _Verification({required this.repository, required this.onSubmitted});

  final HouseholdRepository repository;
  final VoidCallback onSubmitted;

  @override
  State<_Verification> createState() => _VerificationState();
}

class _VerificationState extends State<_Verification> {
  String? _primary;
  String? _secondary;
  String? _idType;
  final _idOtherName = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  late Future<List<VerificationRequest>> _future = widget.repository
      .getVerificationRequests();

  Future<String?> _pick() async {
    const group = XTypeGroup(
      label: 'Verification documents',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf'],
    );
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_primary == null || _secondary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose both required documents.')),
      );
      return;
    }
    if (_idType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose which government ID you are uploading.'),
        ),
      );
      return;
    }
    if (_idType == 'other' && _idOtherName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name the government ID you are uploading.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.submitVerification(
        primaryPath: _primary!,
        secondaryPath: _secondary!,
        primaryIdType: _idType!,
        primaryIdOtherName: _idOtherName.text.trim(),
        notes: _notes.text.trim(),
      );
      widget.onSubmitted();
      setState(() {
        _future = widget.repository.getVerificationRequests();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification submitted for review.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VerificationRequest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () => setState(
              () => _future = widget.repository.getVerificationRequests(),
            ),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final latest = snapshot.data!.isEmpty ? null : snapshot.data!.first;
        final locked = latest != null && latest.status != 'rejected';
        final normalizedStatus = latest?.status.trim().toLowerCase() ?? '';
        final verified =
            normalizedStatus == 'verified' || normalizedStatus == 'approved';
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            if (latest != null)
              _VerificationReadonlyCard(latest: latest, verified: verified),
            if (locked)
              StatusCard(
                icon: verified
                    ? Icons.verified_outlined
                    : Icons.pending_actions_outlined,
                title: verified
                    ? "You're already verified"
                    : 'Verification is under review',
                subtitle: verified
                    ? 'Your verification is already approved by the admin, so the details above are now read-only.'
                    : 'Your documents are locked while the admin reviews your household account.',
                status: latest.status,
              )
            else ...[
              const _VerificationIntro(
                text:
                    'Verification helps workers trust that job postings come from a reviewed household account.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _idType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Which government ID are you uploading?',
                ),
                items: [
                  for (final option in gawagoGovernmentIdTypes)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => setState(() => _idType = value),
              ),
              if (_idType == 'other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _idOtherName,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Name the ID',
                    hintText: 'e.g. PRC Professional ID',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _VerificationDocumentPicker(
                title: 'Primary ID document',
                subtitle: 'A clear photo or scan of the ID you chose above.',
                path: _primary,
                icon: Icons.badge_outlined,
                onPick: () async {
                  final value = await _pick();
                  if (value != null) setState(() => _primary = value);
                },
              ),
              const SizedBox(height: 12),
              _VerificationDocumentPicker(
                title: 'Supporting document',
                subtitle:
                    'Barangay clearance, employment record, or another supporting file.',
                path: _secondary,
                icon: Icons.description_outlined,
                onPick: () async {
                  final value = await _pick();
                  if (value != null) setState(() => _secondary = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional notes (optional)',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _submitting ? 'Submitting...' : 'Submit Documents',
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _VerificationIntro extends StatelessWidget {
  const _VerificationIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.primary.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: GawaGoColors.ink, height: 1.4),
      ),
    );
  }
}

class _VerificationDocumentPicker extends StatelessWidget {
  const _VerificationDocumentPicker({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.icon,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final String? path;
  final IconData icon;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final filename = path == null
        ? 'No file selected'
        : path!.split(RegExp(r'[/\\]')).last;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: GawaGoColors.leafDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: GawaGoColors.textMuted)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.attach_file),
            label: const Text('Choose file'),
          ),
          const SizedBox(height: 6),
          Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _VerificationReadonlyCard extends StatelessWidget {
  const _VerificationReadonlyCard({
    required this.latest,
    required this.verified,
  });

  final VerificationRequest latest;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: latest.status,
              prefix: verified ? null : 'Status',
            ),
          ),
          const SizedBox(height: 16),
          _VerificationDocumentRow(
            title: 'Primary ID',
            value: latest.primaryName,
            actionLabel: 'View Primary ID',
          ),
          _VerificationDocumentRow(
            title: 'Supporting Documents',
            value: latest.secondaryName,
            actionLabel: 'View Supporting Document',
          ),
          if (latest.reviewNote.isNotEmpty)
            _VerificationDocumentRow(
              title: 'Admin Note',
              value: latest.reviewNote,
            ),
        ],
      ),
    );
  }
}

class _VerificationDocumentRow extends StatelessWidget {
  const _VerificationDocumentRow({
    required this.title,
    required this.value,
    this.actionLabel,
  });

  final String title;
  final String value;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(value.isEmpty ? 'Not available' : value),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              actionLabel!,
              style: const TextStyle(
                color: GawaGoColors.panelGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notifications extends StatefulWidget {
  const _Notifications({
    super.key,
    required this.repository,
    required this.onOpenJob,
    required this.onToolbarChanged,
    required this.onNotificationsChanged,
  });

  final HouseholdRepository repository;
  final ValueChanged<int> onOpenJob;
  final VoidCallback onToolbarChanged;
  final VoidCallback onNotificationsChanged;

  @override
  State<_Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends State<_Notifications> {
  late Future<List<WorkerNotification>> _future = widget.repository
      .getNotifications();
  DateTime? _selectedDate;
  bool _markingAllRead = false;

  bool get hasDateFilter => _selectedDate != null;

  Future<void> chooseDate() => _chooseDate();

  void clearDateFilter() {
    if (_selectedDate == null) return;
    setState(() => _selectedDate = null);
    widget.onToolbarChanged();
  }

  Future<void> markAllRead() async {
    if (_markingAllRead) return;
    await _markAllRead(await _future);
  }

  void _reload() {
    setState(() {
      _future = widget.repository.getNotifications();
    });
    widget.onNotificationsChanged();
  }

  Future<void> _viewDetails(WorkerNotification item) async {
    if (!item.isRead) {
      try {
        await widget.repository.markNotificationRead(item.id);
      } catch (_) {
        // Still show the notification; it just stays marked unread.
      }
    }
    if (!mounted) return;
    final jobId = item.targetJobId;
    HouseholdJob? job;
    if (jobId != null) {
      try {
        job = await widget.repository.getJob(jobId);
      } catch (_) {
        job = null;
      }
    }
    if (!mounted) return;
    await _showDetails(item, job: job);
    _reload();
  }

  Future<void> _showDetails(WorkerNotification item, {HouseholdJob? job}) {
    final application = job == null
        ? null
        : _applicationById(job, item.applicationId);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Details'),
        content: _HouseholdNotificationPreview(
          notification: item,
          job: job,
          application: application,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (application != null && job != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(this.context).push(
                  MaterialPageRoute(
                    builder: (_) => _ApplicantDetail(
                      job: job,
                      application: application,
                      repository: widget.repository,
                      onChanged: _reload,
                    ),
                  ),
                );
              },
              child: const Text('View applicant'),
            ),
          if (application == null && item.targetJobId != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenJob(item.targetJobId!);
              },
              child: const Text('View job'),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(WorkerNotification item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This notification will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteNotification(item.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't delete that notification. Please try again.",
            ),
          ),
        );
      }
      return;
    }
    _reload();
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
      widget.onToolbarChanged();
    }
  }

  Future<void> _markAllRead(List<WorkerNotification> notifications) async {
    final unread = notifications.where((item) => !item.isRead).toList();
    if (unread.isEmpty) return;
    setState(() => _markingAllRead = true);
    try {
      for (final item in unread) {
        await widget.repository.markNotificationRead(item.id);
      }
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkerNotification>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final notifications = snapshot.data!;
        final visible = _selectedDate == null
            ? notifications
            : notifications.where((item) {
                final date = item.createdDate;
                return date != null &&
                    date.year == _selectedDate!.year &&
                    date.month == _selectedDate!.month &&
                    date.day == _selectedDate!.day;
              }).toList();
        final selectedDateLabel = _selectedDate == null
            ? null
            : 'Filtered: ${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}';
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            NotificationControlsCard(
              selectedDateLabel: selectedDateLabel,
              markingAllRead: _markingAllRead,
              onChooseDate: _chooseDate,
              onClearDate: clearDateFilter,
              onMarkAllRead: markAllRead,
            ),
            if (notifications.isEmpty)
              const AppEmptyState(message: 'No notifications.')
            else if (visible.isEmpty)
              const AppEmptyState(
                message: 'No notifications found for the selected date.',
              ),
            ...visible.map(
              (item) => StatusCard(
                icon: item.requiresAction
                    ? Icons.notification_important_outlined
                    : Icons.notifications_none,
                title: item.title,
                status: item.requiresAction ? 'Action Required' : null,
                subtitle: '${item.message}\n${item.displayDate}',
                emphasized: !item.isRead,
                trailing: NotificationActionMenu(
                  showMarkRead: !item.isRead,
                  onSelected: (value) async {
                    if (value == 'details') {
                      await _viewDetails(item);
                    } else if (value == 'read') {
                      try {
                        await widget.repository.markNotificationRead(item.id);
                      } catch (_) {
                        return;
                      }
                      _reload();
                    } else {
                      await _delete(item);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HouseholdNotificationPreview extends StatelessWidget {
  const _HouseholdNotificationPreview({
    required this.notification,
    required this.job,
    required this.application,
  });

  final WorkerNotification notification;
  final HouseholdJob? job;
  final HouseholdApplication? application;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.message),
          const SizedBox(height: 12),
          Text(
            notification.displayDate,
            style: const TextStyle(color: GawaGoColors.textMuted),
          ),
          if (application != null) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: GawaGoColors.surfaceMuted,
                  child: Text(
                    _initial(application!.workerName),
                    style: const TextStyle(
                      fontFamily: GawaGoColors.fontHeading,
                      color: GawaGoColors.textMuted,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application!.workerName.isEmpty
                            ? application!.workerUsername
                            : application!.workerName,
                        style: const TextStyle(
                          fontFamily: GawaGoColors.fontHeading,
                          color: GawaGoColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Worker profile summary is available in full details.',
                        style: TextStyle(color: GawaGoColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CompactProfileFact(
              label: 'Verification',
              value: formatStatus(application!.workerVerificationStatus),
            ),
            _CompactProfileFact(
              label: 'Rating',
              value: application!.workerRatingLabel,
            ),
            _CompactProfileFact(
              label: 'Worker Rate',
              value: application!.workerRateLabel,
            ),
          ],
          if (job != null) ...[
            const SizedBox(height: 12),
            _CompactProfileFact(label: 'Job', value: job!.title),
            _CompactProfileFact(label: 'Location', value: job!.locationLabel),
            _CompactProfileFact(
              label: 'Rate',
              value:
                  'PHP ${job!.serviceRate.toStringAsFixed(2)} / ${job!.rateTypeLabel}',
            ),
          ],
        ],
      ),
    );
  }
}

TileLayer _tiles() => osmTileLayer();

HouseholdApplication? _applicationForWorker(
  HouseholdJob job,
  RecommendedWorker worker,
) {
  for (final application in job.applications) {
    if (application.workerUsername.isNotEmpty &&
        application.workerUsername == worker.username) {
      return application;
    }
    if (application.workerName.isNotEmpty &&
        application.workerName == worker.username) {
      return application;
    }
  }
  return null;
}

HouseholdApplication? _applicationById(HouseholdJob job, int? applicationId) {
  if (applicationId == null) return null;
  for (final application in job.applications) {
    if (application.id == applicationId) return application;
  }
  return null;
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: GawaGoColors.border),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

/// Post-a-job landing screen: the workers the AI recommender ranked highest
/// for the job that was just created.
typedef _ScatterTag = ({
  String label,
  double baseLeft,
  double baseTop,
  double left,
  double top,
  double rotate,
});

/// The animated "finding workers" moment shown right after posting a job,
/// while the AI match is computed -- mirrors web's .worker-ai-hero
/// (AppViews.jsx: HOUSEHOLD_SCAN_STATUS_PHASES, householdScatterTags).
/// Floating skill-tag chips jitter in place and the status line cycles
/// through the same three phases web uses, so posting a job feels the same
/// on both platforms instead of mobile just showing a bare spinner.
class _FindingWorkersHero extends StatefulWidget {
  const _FindingWorkersHero({required this.job});

  final HouseholdJob job;

  @override
  State<_FindingWorkersHero> createState() => _FindingWorkersHeroState();
}

class _FindingWorkersHeroState extends State<_FindingWorkersHero> {
  static const _phases = [
    'Scanning available workers nearby…',
    'Comparing worker skills to your job…',
    'Ranking by skill fit and travel distance…',
  ];

  final _random = math.Random();
  int _phaseIndex = 0;
  late List<_ScatterTag> _tags = _buildTags();
  Timer? _phaseTimer;
  Timer? _jitterTimer;

  @override
  void initState() {
    super.initState();
    _phaseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _phaseIndex = (_phaseIndex + 1) % _phases.length);
    });
    _jitterTimer = Timer.periodic(const Duration(milliseconds: 620), (_) {
      if (!mounted) return;
      setState(() => _tags = _tags.map(_jitter).toList());
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _jitterTimer?.cancel();
    super.dispose();
  }

  List<_ScatterTag> _buildTags() {
    final labels = <String>{
      widget.job.requiredSkill,
      widget.job.jobType,
      'Skill match',
      'Verified workers',
      'Travel distance',
      'Nearby workers',
    }.where((label) => label.trim().isNotEmpty).take(6).toList();
    final tags = <_ScatterTag>[
      for (var i = 0; i < labels.length; i++)
        (
          label: labels[i],
          baseLeft: (i % 3) * 30.0 + 4,
          baseTop: (i ~/ 3) * 38.0 + 6,
          left: 0,
          top: 0,
          rotate: 0,
        ),
    ];
    return tags.map(_jitter).toList();
  }

  _ScatterTag _jitter(_ScatterTag tag) => (
    label: tag.label,
    baseLeft: tag.baseLeft,
    baseTop: tag.baseTop,
    left: tag.baseLeft + _random.nextDouble() * 8,
    top: tag.baseTop + _random.nextDouble() * 10,
    rotate: _random.nextDouble() * 16 - 8,
  );

  @override
  Widget build(BuildContext context) {
    final stageWidth = MediaQuery.sizeOf(context).width - 24 - 40;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GawaGoColors.deepGreen, GawaGoColors.cardGreen],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'JOB POSTED',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Finding workers for your job',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.job.title.isEmpty ? "Your job" : widget.job.title} is live. '
            "We're matching it to available workers nearby by skill fit and "
            'travel distance.',
            style: const TextStyle(
              color: GawaGoColors.leafLine,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 130,
            width: double.infinity,
            child: Stack(
              children: _tags
                  .map(
                    (tag) => AnimatedPositioned(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      left: stageWidth > 0
                          ? (tag.left / 100).clamp(0.0, 1.0) * stageWidth
                          : 0,
                      top: tag.top,
                      child: Transform.rotate(
                        angle: tag.rotate * math.pi / 180,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            tag.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                _phases[_phaseIndex],
                key: ValueKey(_phaseIndex),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobMatches extends StatefulWidget {
  const _JobMatches({
    required this.repository,
    required this.job,
    required this.onChanged,
    required this.onOpenJob,
  });

  final HouseholdRepository repository;
  final HouseholdJob job;
  final VoidCallback onChanged;
  final Future<void> Function(int jobId) onOpenJob;

  @override
  State<_JobMatches> createState() => _JobMatchesState();
}

class _JobMatchesState extends State<_JobMatches> {
  // Mirrors web's AI_SCAN_MIN_DURATION_MS (AppViews.jsx): the animated
  // "finding workers" moment stays up at least this long even if the API
  // responds instantly, so it reads as a real search rather than a flicker.
  static const _minScanDuration = Duration(milliseconds: 2400);

  late Future<List<RecommendedWorker>> _future = _load();
  bool _minDurationElapsed = false;
  String _skillFilter = 'All';
  bool _mapView = false;
  // widget.job is a snapshot from when this screen opened and never
  // refreshes, so a sent request never showed on the card and a second tap
  // could re-POST it (F-10). These track what's actually happened this
  // session, independent of that stale snapshot.
  final Set<int> _sendingWorkerIds = {};
  final Set<int> _sentWorkerIds = {};

  Future<void> _sendRequest(RecommendedWorker worker) async {
    if (_sendingWorkerIds.contains(worker.id)) return;
    setState(() => _sendingWorkerIds.add(worker.id));
    try {
      final sent = await _hireRecommendedWorker(
        context: context,
        repository: widget.repository,
        job: widget.job,
        worker: worker,
        onChanged: widget.onChanged,
      );
      if (mounted && sent) setState(() => _sentWorkerIds.add(worker.id));
    } finally {
      if (mounted) setState(() => _sendingWorkerIds.remove(worker.id));
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(_minScanDuration, () {
      if (mounted) setState(() => _minDurationElapsed = true);
    });
  }

  Future<List<RecommendedWorker>> _load() =>
      widget.repository.getRecommendedWorkers(widget.job.id, rank: 'ai');

  void _reload() {
    // Block body, not an arrow body -- see the other _reload() fixes above
    // for why an arrow body here throws "setState() callback argument
    // returned a Future" at runtime.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedDetailScaffold(
      title: 'Recommended Workers',
      child: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<RecommendedWorker>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  AppErrorState(error: snapshot.error, onRetry: _reload),
                ],
              );
            }
            if (!snapshot.hasData || !_minDurationElapsed) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [_FindingWorkersHero(job: widget.job)],
              );
            }
            final workers = snapshot.data!;
            // Chips come from the skills these matches actually list, so the
            // row never offers a filter that empties the list.
            final skillOptions = <String>[
              'All',
              ...{for (final worker in workers) ...worker.skills},
            ];
            if (!skillOptions.contains(_skillFilter)) {
              _skillFilter = 'All';
            }
            final visible = _skillFilter == 'All'
                ? workers
                : workers
                      .where((worker) => worker.skills.contains(_skillFilter))
                      .toList();
            final viewToggle = ListMapViewToggle(
              mapView: _mapView,
              onChanged: (value) => setState(() => _mapView = value),
            );

            // The map owns drag gestures, so it can't sit inside the
            // scrolling list: Map View fills the screen below the toggle
            // instead. Mirrors the worker's Find Jobs map.
            if (_mapView) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    viewToggle,
                    const SizedBox(height: 10),
                    const Text(
                      'Every matched worker is pinned by their general area. '
                      "Tap a pin to see who's available there.",
                      style: TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: HouseholdWorkersMap(
                        workers: visible,
                        // HouseholdJob defaults a missing coordinate to 0,
                        // which would pin the job site off the coast of
                        // Africa rather than nowhere.
                        jobLatitude: widget.job.latitude == 0
                            ? null
                            : widget.job.latitude,
                        jobLongitude: widget.job.longitude == 0
                            ? null
                            : widget.job.longitude,
                        onViewProfile: (worker) => _showWorkerMatchProfile(
                          context,
                          repository: widget.repository,
                          job: widget.job,
                          worker: worker,
                          onChanged: widget.onChanged,
                        ),
                        onHire: (worker) => _sendRequest(worker),
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _MatchesHeader(
                  jobTitle: widget.job.title,
                  skillOptions: skillOptions,
                  selected: _skillFilter,
                  onSelect: (value) => setState(() => _skillFilter = value),
                ),
                const SizedBox(height: 14),
                viewToggle,
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  _DashedEmptyBox(
                    message: workers.isEmpty
                        ? 'No workers matched this job yet. Workers need listed '
                              'skills, a saved location, and must fall inside the '
                              "job's search radius."
                        : 'No matched worker lists $_skillFilter yet. Pick another '
                              'category to see the rest.',
                  )
                else
                  ...visible.map(
                    (worker) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: WorkerMatchCard(
                        name: worker.displayName,
                        locationLabel: worker.locationLabel,
                        photoUrl: worker.profilePhotoUrl,
                        verified:
                            worker.verificationStatus.toLowerCase() ==
                            'verified',
                        matchScore: worker.aiScore,
                        ratingLabel: worker.ratingLabel,
                        ratingCount: worker.ratingCount,
                        distanceLabel: worker.distanceLabel,
                        completedJobs: worker.completedJobs,
                        rateLabel: _shortRate(worker.workerRate),
                        skills: worker.skills,
                        bio: worker.bio,
                        breakdown: AiMatchBreakdown(
                          skillSharePercent: worker.skillSharePercent,
                          exactSkillMatch: worker.exactSkillMatch,
                        ),
                        requestSent:
                            _sentWorkerIds.contains(worker.id) ||
                            _applicationForWorker(
                                  widget.job,
                                  worker,
                                )?.status.toLowerCase() ==
                                'hire_requested',
                        onViewProfile: () => _showWorkerMatchProfile(
                          context,
                          repository: widget.repository,
                          job: widget.job,
                          worker: worker,
                          onChanged: widget.onChanged,
                        ),
                        onSendRequest: _sendingWorkerIds.contains(worker.id)
                            ? () {}
                            : () => _sendRequest(worker),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton(
                  onPressed: () => widget.onOpenJob(widget.job.id),
                  child: const Text('View Job Details'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "PHP 650.00 / Per Day" -> "PHP 650/day", so the rate still fits the pill
/// that sits over a match card's photo.
String _shortRate(String rate) {
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rate);
  if (match == null) return rate;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null) return rate;
  final whole = amount.truncateToDouble() == amount
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final lower = rate.toLowerCase();
  if (lower.contains('hour')) return 'PHP $whole/hr';
  if (lower.contains('fixed')) return 'PHP $whole fixed';
  return 'PHP $whole/day';
}

/// Page heading for the AI match list: the eyebrow/title/weights line, the
/// live-matches badge, and the skill filter row.
class _MatchesHeader extends StatelessWidget {
  const _MatchesHeader({
    required this.jobTitle,
    required this.skillOptions,
    required this.selected,
    required this.onSelect,
  });

  final String jobTitle;
  final List<String> skillOptions;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'AI MATCHED WORKERS',
                style: TextStyle(
                  color: GawaGoColors.leafDeep,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: GawaGoColors.leafTint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircleAvatar(
                    radius: 3,
                    backgroundColor: GawaGoColors.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Live matches',
                    style: TextStyle(
                      color: GawaGoColors.leafDeep,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          jobTitle,
          style: const TextStyle(
            fontFamily: GawaGoColors.fontHeading,
            color: GawaGoColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ranked by skill fit (70%) and travel distance (30%).',
          style: TextStyle(color: GawaGoColors.textMuted, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: skillOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final skill = skillOptions[index];
              final active = skill == selected;
              return GestureDetector(
                onTap: () => onSelect(skill),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: active ? GawaGoColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active
                          ? GawaGoColors.ink
                          : GawaGoColors.lineStrong,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    skill,
                    style: TextStyle(
                      color: active
                          ? GawaGoColors.cream
                          : GawaGoColors.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
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

/// Send a hire request to a recommended worker.
///
/// Shared by the job detail panel and the post-a-job matches screen. The
/// guards mirror the backend's own rules so the household gets an immediate
/// answer instead of a round-trip failure.
/// Returns true when a hire or a hire request actually went through, so
/// callers that track their own "sent" state (e.g. _JobMatches, F-10) know
/// to update it -- this function swallows its own errors into a snackbar
/// rather than throwing, so the return value is the only success signal.
Future<bool> _hireRecommendedWorker({
  required BuildContext context,
  required HouseholdRepository repository,
  required HouseholdJob job,
  required RecommendedWorker worker,
  required VoidCallback onChanged,
}) async {
  void notify(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  if (worker.verificationStatus.trim().toLowerCase() != 'verified') {
    notify('This worker must be verified before they can be hired.');
    return false;
  }
  if (job.hiredCount >= job.workerSlots) {
    notify('This job already has enough hired workers.');
    return false;
  }

  final existing = _applicationForWorker(job, worker);
  final existingStatus = existing?.status.trim().toLowerCase();
  if (existingStatus == 'hired') {
    notify('This worker is already hired for this job.');
    return false;
  }
  if (existingStatus == 'hire_requested') {
    notify('A hire request was already sent to this worker.');
    return false;
  }

  try {
    // Same hybrid rule as the website: a worker who applied is hired
    // outright (applying is consent); one who never applied is invited and
    // confirms first.
    if (existingStatus == 'pending') {
      await repository.setApplicationStatus(existing!.id, 'hired');
      onChanged();
      notify('${worker.name} is hired. The job is now in progress.');
      return true;
    }
    if (existing != null) {
      await repository.setApplicationStatus(existing.id, 'hire_requested');
    } else {
      await repository.sendHireRequest(job.id, worker.id);
    }
    onChanged();
    notify('Request sent. The worker can accept or reject it.');
    return true;
  } catch (error) {
    notify(friendlyApiError(error));
    return false;
  }
}

String _title(_Page page) => switch (page) {
  _Page.dashboard => 'Dashboard',
  _Page.postJob => 'Post a Job',
  _Page.jobs => 'My Jobs',
  _Page.messages => 'Messages',
  _Page.myReports => 'My Complaints',
  _Page.profile => 'My Profile',
  _Page.reviews => 'Reviews & Feedback',
  _Page.verification => 'Get Verified',
  _Page.notifications => 'Notifications',
};

IconData _icon(_Page page) => switch (page) {
  _Page.dashboard => Icons.dashboard_outlined,
  _Page.postJob => Icons.post_add,
  _Page.jobs => Icons.work_outline,
  _Page.messages => Icons.chat_bubble_outline,
  _Page.myReports => Icons.flag_outlined,
  _Page.profile => Icons.person_outline,
  _Page.reviews => Icons.star_outline,
  _Page.verification => Icons.verified_outlined,
  _Page.notifications => Icons.notifications_none,
};

double _coordinateForApi(double value) =>
    double.parse(value.toStringAsFixed(7));

/// Everything the household-facing worker profile renders, normalised so the
/// same screen serves an applicant and a Smart-Matched / AI-recommended
/// worker. The two sources carry different shapes; only this class knows.
class _WorkerProfileSubject {
  const _WorkerProfileSubject({
    required this.workerId,
    required this.username,
    required this.displayName,
    required this.photoUrl,
    required this.verificationStatus,
    required this.locationLabel,
    required this.ratingLabel,
    required this.completedJobs,
    required this.bio,
    required this.skills,
    required this.hourlyRate,
    required this.dailyRate,
    required this.rateFallback,
    required this.yearsExperience,
    required this.distanceKm,
    required this.distanceLabel,
    required this.matchScore,
    required this.matchBasis,
  });

  final int workerId;
  final String username;
  final String displayName;
  final String photoUrl;
  final String verificationStatus;
  final String locationLabel;
  final String ratingLabel;
  final int completedJobs;
  final String bio;
  final List<String> skills;

  /// Applicants expose the two numeric rates; a recommendation only carries
  /// a pre-formatted label, so exactly one of these paths has data.
  final double? hourlyRate;
  final double? dailyRate;
  final String rateFallback;

  final int? yearsExperience;
  final double? distanceKm;
  final String distanceLabel;

  /// 0-1. Null hides the Match Score card entirely rather than showing 0%.
  final double? matchScore;

  /// What that score was computed from. Smart Matching and the AI recommender
  /// rank on different things and are specified as complementary, so the card
  /// never claims one did the other's job.
  final String matchBasis;

  bool get isVerified => verificationStatus.trim().toLowerCase() == 'verified';

  /// "Hire Maria" reads better than "Hire Maria Santos" in a top bar.
  String get firstName {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
  }

  factory _WorkerProfileSubject.fromApplication(HouseholdApplication item) {
    final name = item.workerName.trim().isEmpty
        ? item.workerUsername
        : item.workerName;
    return _WorkerProfileSubject(
      workerId: item.workerId,
      username: item.workerUsername,
      displayName: name,
      photoUrl: item.workerProfilePhotoUrl,
      verificationStatus: item.workerVerificationStatus,
      locationLabel: item.locationLabel,
      ratingLabel: item.workerRatingLabel,
      completedJobs: item.workerCompletedJobs,
      bio: item.workerBio,
      skills: item.workerSkills,
      hourlyRate: item.workerHourlyRate,
      dailyRate: item.workerDailyRate,
      rateFallback: item.workerRateLabel,
      yearsExperience: item.workerYearsExperience,
      distanceKm: item.distanceKm,
      distanceLabel: item.distanceLabel,
      matchScore: item.workerMatchScore,
      matchBasis: 'Based on verification, skills and distance',
    );
  }

  factory _WorkerProfileSubject.fromRecommendation(RecommendedWorker worker) {
    return _WorkerProfileSubject(
      workerId: worker.id,
      username: worker.username,
      displayName: worker.displayName,
      photoUrl: worker.profilePhotoUrl,
      verificationStatus: worker.verificationStatus,
      locationLabel: worker.locationLabel,
      ratingLabel: worker.ratingLabel,
      completedJobs: worker.completedJobs,
      bio: worker.bio,
      skills: worker.skills,
      hourlyRate: null,
      dailyRate: null,
      rateFallback: worker.workerRate,
      yearsExperience: null,
      distanceKm: worker.distanceKm,
      distanceLabel: worker.distanceLabel,
      matchScore: worker.aiScore > 0 ? worker.aiScore : null,
      matchBasis: 'Based on skill fit & distance',
    );
  }
}

/// The profile a household reads before hiring. Replaces the old applicant
/// summary, which only showed what the application payload happened to
/// carry; this also pulls the worker's public portfolio and job history.
class _WorkerProfileScreen extends StatefulWidget {
  const _WorkerProfileScreen({
    required this.subject,
    required this.repository,
    required this.onHire,
    required this.hireEnabled,
    this.hireLabel,
    this.matchBreakdown,
    this.mapPanel,
    this.bottomActions = const [],
  });

  final _WorkerProfileSubject subject;
  final HouseholdRepository repository;
  final VoidCallback onHire;
  final bool hireEnabled;

  /// Overrides `Hire <first name>` when the offer has already been made, so
  /// the button states what happened instead of sitting there dead.
  final String? hireLabel;

  /// The skill-vs-proximity bar that explains an AI score. Smart Matching
  /// ranks on a rule order rather than weighted contributions, so an
  /// applicant has nothing to break down and passes null.
  final Widget? matchBreakdown;

  /// The applicant route shows the worker-to-job driving route; a
  /// recommendation card has already shown its own distance.
  final Widget? mapPanel;

  final List<Widget> bottomActions;

  @override
  State<_WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<_WorkerProfileScreen> {
  late final Future<WorkerPortfolio> _portfolio = widget.repository
      .getWorkerPortfolio(widget.subject.workerId);
  late final Future<List<WorkerJobHistoryEntry>> _history = widget.repository
      .getWorkerJobHistory(widget.subject.workerId);
  late final Future<List<GawaGoReview>> _reviews = widget.repository
      .getWorkerReviews(widget.subject.username);

  String get _hireText =>
      widget.hireLabel ?? 'Hire ${widget.subject.firstName}';

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return AuthenticatedDetailScaffold(
      title: 'Worker Profile',
      actions: [
        // The detail top bar is deep green, so this pill uses the lighter
        // brand green rather than the card button's deepGreen -- that would
        // vanish into the bar.
        SizedBox(
          height: 38,
          child: FilledButton(
            onPressed: widget.hireEnabled ? widget.onHire : null,
            style: FilledButton.styleFrom(
              backgroundColor: GawaGoColors.primary,
              foregroundColor: GawaGoColors.onPrimary,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontFamily: GawaGoColors.fontBody,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: Text(_hireText, maxLines: 1),
          ),
        ),
      ],
      bottomNavigationBar: widget.bottomActions.isEmpty
          ? null
          : PersistentActionBar(children: widget.bottomActions),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _WorkerProfileHeaderCard(
            subject: subject,
            hireLabel: _hireText,
            onHire: widget.hireEnabled ? widget.onHire : null,
          ),
          if (subject.matchScore != null) ...[
            const SizedBox(height: 14),
            _MatchScoreCard(
              score: subject.matchScore!,
              basis: subject.matchBasis,
              breakdown: widget.matchBreakdown,
            ),
          ],
          const SizedBox(height: 14),
          ProfileSection(
            title: 'About',
            child: subject.bio.trim().isEmpty
                ? const SectionEmptyText('No description provided yet.')
                : Text(
                    subject.bio.trim(),
                    style: const TextStyle(
                      color: GawaGoColors.text,
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<WorkerPortfolio>(
            future: _portfolio,
            builder: (context, snapshot) {
              final portfolio = snapshot.data ?? WorkerPortfolio.empty;
              final failed = snapshot.hasError;
              final loading = !snapshot.hasData && !failed;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileSection(
                    title: 'Skills & Expertise',
                    child: _portfolioBody(
                      loading: loading,
                      failed: failed,
                      empty: portfolio.skills.isEmpty,
                      emptyText: 'No skills added yet.',
                      builder: () => Column(
                        children: portfolio.skills
                            .map(
                              (skill) => ProfileSkillTile(
                                skillName: skill.skillName,
                                proficiencyLabel: skill.proficiencyLabel,
                                averageRating: skill.averageRating,
                                ratingCount: skill.ratingCount,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ProfileSection(
                    title: 'Certifications',
                    child: _portfolioBody(
                      loading: loading,
                      failed: failed,
                      empty: portfolio.certifications.isEmpty,
                      emptyText: 'No certifications added yet.',
                      builder: () => Column(
                        children: portfolio.certifications
                            .map(
                              (certificate) => _ReadOnlyCertificationTile(
                                certificate: certificate,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ProfileSection(
                    title: 'Work Samples',
                    child: _portfolioBody(
                      loading: loading,
                      failed: failed,
                      empty: portfolio.workSamples.isEmpty,
                      emptyText: 'No work samples uploaded yet.',
                      builder: () => Column(
                        children: portfolio.workSamples
                            .map(
                              (sample) =>
                                  _ReadOnlyWorkSampleTile(sample: sample),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ProfileSection(
            title: 'Employment History',
            child: FutureBuilder<List<WorkerJobHistoryEntry>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SectionEmptyText(
                    'Could not load this worker\'s job history right now.',
                  );
                }
                final jobs = snapshot.data;
                if (jobs == null) return const _SectionLoading();
                if (jobs.isEmpty) {
                  return const SectionEmptyText('No completed jobs yet.');
                }
                return Column(
                  children: jobs
                      .map((entry) => _EmploymentHistoryRow(entry: entry))
                      .toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          ProfileSection(
            title: 'Recent Feedback',
            child: FutureBuilder<List<GawaGoReview>>(
              future: _reviews,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SectionEmptyText(
                    'Could not load feedback right now.',
                  );
                }
                final reviews = snapshot.data;
                if (reviews == null) return const _SectionLoading();
                final withContent = reviews
                    .where(
                      (review) =>
                          review.feedback.trim().isNotEmpty ||
                          review.rating != null,
                    )
                    .take(3)
                    .toList();
                if (withContent.isEmpty) {
                  return const SectionEmptyText('No feedback submitted yet.');
                }
                return Column(
                  children: withContent
                      .map((review) => _ApplicantFeedbackItem(review: review))
                      .toList(),
                );
              },
            ),
          ),
          if (widget.mapPanel != null) ...[
            const SizedBox(height: 18),
            widget.mapPanel!,
          ],
        ],
      ),
    );
  }

  Widget _portfolioBody({
    required bool loading,
    required bool failed,
    required bool empty,
    required String emptyText,
    required Widget Function() builder,
  }) {
    if (failed) {
      return const SectionEmptyText(
        'Could not load this worker\'s portfolio right now.',
      );
    }
    if (loading) return const _SectionLoading();
    if (empty) return SectionEmptyText(emptyText);
    return builder();
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// Cover photo, identity, the facts a household decides on, and the primary
/// hire action.
class _WorkerProfileHeaderCard extends StatelessWidget {
  const _WorkerProfileHeaderCard({
    required this.subject,
    required this.hireLabel,
    required this.onHire,
  });

  final _WorkerProfileSubject subject;
  final String hireLabel;
  final VoidCallback? onHire;

  @override
  Widget build(BuildContext context) {
    const bannerHeight = 168.0;
    const avatarRadius = 38.0;
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
          SizedBox(
            height: bannerHeight + avatarRadius,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: bannerHeight,
                  child: _ProfileBanner(subject: subject),
                ),
                if (subject.isVerified)
                  const Positioned(
                    top: 14,
                    left: 14,
                    child: _VerifiedOverlayPill(),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: GawaGoColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: WorkerPhoto(
                        photoUrl: subject.photoUrl,
                        name: subject.displayName,
                        size: avatarRadius * 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subject.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '@${subject.username}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 10),
          const Center(child: SoftGreenPill(label: 'Worker')),
          const SizedBox(height: 18),
          const Divider(height: 1, color: GawaGoColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileFactRow(
                  label: 'Barangay',
                  value: subject.locationLabel.isEmpty
                      ? 'Not set'
                      : subject.locationLabel,
                ),
                if (subject.yearsExperience != null)
                  _ProfileFactRow(
                    label: 'Experience',
                    value:
                        '${subject.yearsExperience} '
                        '${subject.yearsExperience == 1 ? 'year' : 'years'}',
                  ),
                if (subject.distanceKm != null)
                  _ProfileFactRow(
                    label: 'Distance',
                    value: '${subject.distanceKm!.toStringAsFixed(1)} km away',
                  )
                else if (subject.distanceLabel.isNotEmpty)
                  _ProfileFactRow(
                    label: 'Distance',
                    value: subject.distanceLabel,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: GawaGoColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Verification: ',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    StatusBadge(status: subject.verificationStatus),
                  ],
                ),
                const SizedBox(height: 8),
                _ProfileFactRow(
                  label: 'Rating',
                  value: subject.ratingLabel.isEmpty
                      ? 'No ratings yet'
                      : subject.ratingLabel,
                ),
                _ProfileFactRow(
                  label: 'Jobs Done',
                  value: '${subject.completedJobs}',
                ),
                if (subject.hourlyRate != null ||
                    subject.dailyRate != null) ...[
                  _ProfileFactRow(
                    label: 'Hourly Rate',
                    value: subject.hourlyRate == null
                        ? 'Not disclosed'
                        : 'PHP ${subject.hourlyRate!.toStringAsFixed(2)}',
                  ),
                  _ProfileFactRow(
                    label: 'Daily Rate',
                    value: subject.dailyRate == null
                        ? 'Not disclosed'
                        : 'PHP ${subject.dailyRate!.toStringAsFixed(2)}',
                  ),
                ] else
                  _ProfileFactRow(
                    label: 'Rate',
                    value: subject.rateFallback.isEmpty
                        ? 'Not disclosed'
                        : subject.rateFallback,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: GawaGoColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subject.skills.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subject.skills
                        .map((skill) => _NeutralChip(label: skill))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: onHire,
                    style: FilledButton.styleFrom(
                      backgroundColor: GawaGoColors.primary,
                      foregroundColor: GawaGoColors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    child: Text(hireLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The worker's own photo as a cover image. There is only one photo on a
/// profile, so it doubles as the banner; with none, a flat brand panel keeps
/// the card's shape instead of collapsing it.
class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.subject});

  final _WorkerProfileSubject subject;

  @override
  Widget build(BuildContext context) {
    if (subject.photoUrl.isEmpty) {
      return Container(color: GawaGoColors.deepGreen);
    }
    return Image.network(
      subject.photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: GawaGoColors.deepGreen),
    );
  }
}

class _VerifiedOverlayPill extends StatelessWidget {
  const _VerifiedOverlayPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: GawaGoColors.deepGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '✓ Verified',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _MatchScoreCard extends StatelessWidget {
  const _MatchScoreCard({
    required this.score,
    required this.basis,
    this.breakdown,
  });

  final double score;
  final String basis;
  final Widget? breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              WorkerMatchRing(score: score, size: 58),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Match Score',
                      style: TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        color: GawaGoColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      basis,
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ?breakdown,
        ],
      ),
    );
  }
}

class _ProfileFactRow extends StatelessWidget {
  const _ProfileFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: GawaGoColors.textMuted),
            ),
          ],
        ),
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _NeutralChip extends StatelessWidget {
  const _NeutralChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ReadOnlyCertificationTile extends StatelessWidget {
  const _ReadOnlyCertificationTile({required this.certificate});

  final WorkerCertificate certificate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The file route needs the bearer token, which Image.network
          // can't send; PDFs get a pointer to the website instead.
          if (certificate.fileUrl.isNotEmpty && certificate.isImage)
            AuthenticatedImage(url: certificate.fileUrl, height: 160)
          else if (certificate.fileUrl.isNotEmpty)
            CertificateFileNote(isPdf: certificate.isPdf),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  certificate.certificateName,
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (certificate.certificateTypeLabel.isNotEmpty)
                      SoftGreenPill(
                        label: certificate.certificateTypeLabel,
                        muted: true,
                      ),
                    SoftGreenPill(
                      label: certificate.isVerified
                          ? 'Verified'
                          : formatStatus(certificate.verificationStatus),
                      muted: !certificate.isVerified,
                    ),
                  ],
                ),
                if (certificate.issuer.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Issued by ${certificate.issuer}',
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyWorkSampleTile extends StatelessWidget {
  const _ReadOnlyWorkSampleTile({required this.sample});

  final WorkSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sample.title.isEmpty ? 'Untitled sample' : sample.title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _WorkSampleThumb(
                  url: sample.beforeOrFallback,
                  caption: 'Before',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WorkSampleThumb(
                  url: sample.afterImageUrl,
                  caption: 'After',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkSampleThumb extends StatelessWidget {
  const _WorkSampleThumb({required this.url, required this.caption});

  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 110,
            width: double.infinity,
            child: url.isEmpty
                ? Container(color: GawaGoColors.border)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: GawaGoColors.border),
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          caption,
          style: const TextStyle(
            color: GawaGoColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _EmploymentHistoryRow extends StatelessWidget {
  const _EmploymentHistoryRow({required this.entry});

  final WorkerJobHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final period = entry.periodLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GawaGoColors.leafTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.work_outline,
              size: 20,
              color: GawaGoColors.deepGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.isEmpty ? entry.jobType : entry.title,
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.householdName.isEmpty
                      ? 'Household'
                      : entry.householdName,
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 13.5,
                  ),
                ),
                if (entry.locationLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.locationLabel,
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (period.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    period,
                    style: const TextStyle(
                      color: GawaGoColors.textFaint,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                JobSkillRatingChips(
                  ratings: [
                    for (final rating in entry.skillRatings)
                      MapEntry(rating.skillName, rating.rating),
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

/// Shown on an applicant's profile until they are hired for this job: the
/// road distance only, since the API withholds their exact location and
/// route before then.
class _WorkerLocationPrivatePanel extends StatelessWidget {
  const _WorkerLocationPrivatePanel({required this.distanceLabel});

  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: GawaGoColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distanceLabel.isEmpty
                      ? 'Road distance unavailable'
                      : distanceLabel,
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "This worker hasn't pinned a location on their profile "
                  'yet, so there is nothing to show on the map.',
                  style: TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
