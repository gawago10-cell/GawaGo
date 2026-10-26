import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../../shared/widgets/job_image_gallery.dart';
import '../../../shared/widgets/list_map_view_toggle.dart';
import '../../../shared/widgets/location_route_map.dart';
import '../../../shared/widgets/my_complaints_view.dart';
import '../../../shared/widgets/notification_badge.dart';
import '../../../shared/widgets/ai_match_breakdown.dart';
import '../../../shared/widgets/authenticated_image.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../../shared/widgets/report_issue_dialog.dart';
import '../../../shared/widgets/review_history.dart';
import '../../../shared/widgets/status_card.dart';
import '../../chat/presentation/conversations_view.dart';
import '../data/worker_models.dart';
import '../data/worker_repository.dart';
import 'worker_jobs_map.dart';

enum _WorkerPage {
  dashboard,
  jobs,
  applications,
  myJobs,
  messages,
  myReports,
  profile,
  reviews,
  notifications,
  verification,
}

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({
    super.key,
    required this.onLogout,
    WorkerRepository? repository,
  }) : repository = repository ?? const WorkerRepository();

  final VoidCallback onLogout;
  final WorkerRepository repository;

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen>
    with WidgetsBindingObserver {
  // Read-only pages that are safe to rebuild when something new arrives;
  // forms and filtered searches are never reset under the user.
  static const _livePages = {
    _WorkerPage.dashboard,
    _WorkerPage.applications,
    _WorkerPage.myJobs,
    _WorkerPage.myReports,
    _WorkerPage.notifications,
  };
  static const _pollInterval = Duration(seconds: 20);
  static const _primaryPages = [
    _WorkerPage.dashboard,
    _WorkerPage.jobs,
    _WorkerPage.applications,
    _WorkerPage.myJobs,
    _WorkerPage.messages,
    _WorkerPage.myReports,
    _WorkerPage.notifications,
  ];

  static const _accountPages = [_WorkerPage.profile, _WorkerPage.verification];

  WorkerRepository get _repository => widget.repository;
  final _notificationKey = GlobalKey<_WorkerNotificationsState>();
  _WorkerPage _page = _WorkerPage.dashboard;
  final Set<_WorkerPage> _visitedPages = {_WorkerPage.dashboard};
  late Future<int> _unreadCount;
  String? _initialJobSkill;
  String? _verificationStatus;
  String? _verificationRequestStatus;
  Timer? _pollTimer;
  int? _lastUnread;
  final Map<_WorkerPage, int> _pageRefresh = {};

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

  String _navLabel(_WorkerPage page) => page == _WorkerPage.verification
      ? verificationNavLabel(_verificationStatus, _verificationRequestStatus)
      : _title(page);

  Future<int> _loadUnreadCount() => _repository.getUnreadNotificationCount();

  void _refreshUnreadCount() {
    setState(() {
      _unreadCount = _loadUnreadCount();
    });
  }

  void _select(_WorkerPage page) {
    setState(() {
      _page = page;
      _visitedPages.add(page);
    });
  }

  void _openJobsForSkill(String? skill) {
    setState(() {
      _initialJobSkill = skill;
      _page = _WorkerPage.jobs;
      _visitedPages.add(_WorkerPage.jobs);
      // Forces Jobs to remount so initialSkill above actually takes effect,
      // even if it was already visited with a different (or no) filter.
      _pageRefresh[_WorkerPage.jobs] =
          (_pageRefresh[_WorkerPage.jobs] ?? 0) + 1;
    });
  }

  Future<void> _logout() async {
    await GawaGoApi.logout();
    await SessionStorage.clear();
    widget.onLogout();
  }

  // Bumps only the affected page's own key instead of a global counter that
  // used to rekey every visited page in the IndexedStack -- including ones
  // with their own unsaved local state (Find Jobs filters, AI-match mode),
  // wiping them on any unrelated action anywhere in the app (F-11).
  // Defaults to whichever page is on screen, since this is always called as
  // a direct result of something the user just did there; callers acting
  // from outside the IndexedStack (a pushed detail route) pass the page
  // that actually needs to refresh.
  /// The pages that read the worker's skills (dashboard skill matches, Find
  /// Jobs match labels), refreshed after a portfolio skill change.
  void _refreshSkillPages() {
    setState(() {
      for (final page in [_WorkerPage.dashboard, _WorkerPage.jobs]) {
        _pageRefresh[page] = (_pageRefresh[page] ?? 0) + 1;
      }
    });
  }

  /// After applying from Find Jobs: everything that lists applications
  /// refreshes, but not Find Jobs itself (see _WorkerJobs.onApplied).
  void _refreshAfterJobAction() {
    setState(() {
      for (final page in [
        _WorkerPage.dashboard,
        _WorkerPage.applications,
        _WorkerPage.myJobs,
      ]) {
        _pageRefresh[page] = (_pageRefresh[page] ?? 0) + 1;
      }
      _unreadCount = _loadUnreadCount();
    });
  }

  void _refreshAll({_WorkerPage? page}) {
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
        actions: _page == _WorkerPage.notifications
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
                    onPressed: () => _select(_WorkerPage.notifications),
                    icon: NotificationBadge(
                      count: snapshot.data ?? 0,
                      child: const Icon(Icons.notifications_none),
                    ),
                  ),
                ),
              ],
        child: IndexedStack(
          index: _WorkerPage.values.indexOf(_page),
          children: [
            for (final page in _WorkerPage.values)
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

  Widget _buildPage(_WorkerPage page) {
    return switch (page) {
      _WorkerPage.dashboard => _WorkerDashboard(
        repository: _repository,
        onOpenJobs: _openJobsForSkill,
      ),
      _WorkerPage.jobs => _WorkerJobs(
        repository: _repository,
        onChanged: _refreshAll,
        onApplied: _refreshAfterJobAction,
        initialSkill: _initialJobSkill,
      ),
      _WorkerPage.applications => _WorkerApplications(repository: _repository),
      _WorkerPage.myJobs => _WorkerMyJobs(
        repository: _repository,
        onChanged: _refreshAll,
      ),
      _WorkerPage.messages => const ConversationsView(role: 'worker'),
      _WorkerPage.myReports => _WorkerMyReports(repository: _repository),
      _WorkerPage.profile => _WorkerProfile(
        repository: _repository,
        onSaved: _refreshAll,
        onSkillsChanged: _refreshSkillPages,
      ),
      _WorkerPage.reviews => ReviewHistory(
        receivedLoader: _repository.getReceivedReviews,
        givenLoader: _repository.getGivenReviews,
        receivedTitle: 'Feedback & Ratings from Households',
        givenTitle: 'Feedback You Gave Households',
      ),
      _WorkerPage.notifications => _WorkerNotifications(
        key: _notificationKey,
        repository: _repository,
        onOpenJob: _openJob,
        onToolbarChanged: () => setState(() {}),
        onNotificationsChanged: _refreshUnreadCount,
      ),
      _WorkerPage.verification => _WorkerVerification(
        repository: _repository,
        onSubmitted: _refreshAll,
      ),
    };
  }

  Future<void> _openJob(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkerJobDetail(
          repository: _repository,
          jobId: id,
          onChanged: () => _refreshAll(page: _WorkerPage.myJobs),
        ),
      ),
    );
  }
}

class _WorkerDashboard extends StatelessWidget {
  const _WorkerDashboard({required this.repository, required this.onOpenJobs});

  final WorkerRepository repository;
  final ValueChanged<String?> onOpenJobs;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([repository.getProfile(), repository.getJobs()]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () => (context as Element).markNeedsBuild(),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final profile = snapshot.data![0] as WorkerProfile;
        final openJobs = snapshot.data![1] as List<WorkerJob>;
        final ratingValue = profile.displayRating;
        return RefreshIndicator(
          onRefresh: () async => (context as Element).markNeedsBuild(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _WorkerWelcomeBand(profile: profile),
              const SizedBox(height: 12),
              _WebsiteMetricGrid(
                metrics: [
                  _WebsiteMetric(
                    label: 'Open Jobs',
                    value: '${openJobs.length}',
                    highlighted: true,
                  ),
                  _WebsiteMetric(
                    label: 'Skill Matches',
                    value: '${_matchingJobCount(openJobs, profile.skills)}',
                  ),
                  _WebsiteMetric(label: 'Your Rating', value: ratingValue),
                  _WebsiteMetric(
                    label: 'Verification',
                    value: formatStatus(profile.verificationStatus),
                    statusValue: profile.verificationStatus,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _JobMarketOverview(
                profile: profile,
                jobs: openJobs,
                onOpenJobs: onOpenJobs,
              ),
            ],
          ),
        );
      },
    );
  }
}

int _matchingJobCount(List<WorkerJob> jobs, List<String> skills) {
  final normalizedSkills = skills.map(_normalizeSkill).toSet();
  return jobs
      .where((job) => _jobMatchesWorkerSkills(job, normalizedSkills))
      .length;
}

String _normalizeSkill(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool _jobMatchesWorkerSkills(WorkerJob job, Set<String> workerSkills) {
  return workerSkills.contains(_normalizeSkill(job.jobType)) ||
      workerSkills.contains(_normalizeSkill(job.requiredSkill));
}

class _WorkerWelcomeBand extends StatelessWidget {
  const _WorkerWelcomeBand({required this.profile});

  final WorkerProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'DASHBOARD',
            style: TextStyle(
              color: GawaGoColors.leafDeep,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Welcome, ${profile.fullName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: gawagoHeading(fontSize: 26, height: 1.2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ReputationBadge(label: profile.reputationLabel),
              if (profile.ratingTrendLabel.isNotEmpty)
                _ReputationBadge(label: profile.ratingTrendLabel),
            ],
          ),
        ],
      ),
    );
  }
}

/// Earned-standing / trend chip shown on the worker's own dashboard.
class _ReputationBadge extends StatelessWidget {
  const _ReputationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1F9EBF5E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.leafLine, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.leafDeep,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WebsiteMetric {
  const _WebsiteMetric({
    required this.label,
    required this.value,
    this.highlighted = false,
    this.statusValue,
  });

  final String label;
  final String value;
  final bool highlighted;
  final String? statusValue;
}

/// The stat row under the welcome band. It scrolls sideways rather than
/// wrapping into a grid so every tile keeps the same height and the numbers
/// stay large on a narrow phone.
class _WebsiteMetricGrid extends StatelessWidget {
  const _WebsiteMetricGrid({required this.metrics});

  final List<_WebsiteMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: metrics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            SizedBox(width: 158, child: _MetricTile(metrics[index])),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.metric);

  final _WebsiteMetric metric;

  @override
  Widget build(BuildContext context) {
    final highlighted = metric.highlighted;
    final hasStatus = metric.statusValue != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: highlighted ? GawaGoColors.primary : GawaGoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: highlighted
            ? null
            : Border.all(color: GawaGoColors.border, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                color: highlighted
                    ? GawaGoColors.onPrimary
                    : GawaGoColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (hasStatus)
            Flexible(child: _LargeStatusBadge(status: metric.statusValue!))
          else
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  metric.value,
                  style: TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: highlighted
                        ? GawaGoColors.onPrimary
                        : GawaGoColors.ink,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
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

class _LargeStatusBadge extends StatelessWidget {
  const _LargeStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: GawaGoColors.leafTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.leafLine, width: 1.5),
      ),
      child: Text(
        formatStatus(status),
        style: const TextStyle(
          color: GawaGoColors.leafDeep,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _JobMarketOverview extends StatefulWidget {
  const _JobMarketOverview({
    required this.profile,
    required this.jobs,
    required this.onOpenJobs,
  });

  final WorkerProfile profile;
  final List<WorkerJob> jobs;
  final ValueChanged<String?> onOpenJobs;

  @override
  State<_JobMarketOverview> createState() => _JobMarketOverviewState();
}

class _JobMarketOverviewState extends State<_JobMarketOverview> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final visibleSkills = gawagoSkills
        .where((skill) => !isOtherSkillChoice(skill))
        .where((skill) => query.isEmpty || skill.toLowerCase().contains(query))
        .toList();
    final workerSkills = widget.profile.skills.map(_normalizeSkill).toSet();

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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Job Market Overview',
                  style: TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: GawaGoColors.ink,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  style: const TextStyle(fontSize: 15, letterSpacing: 0),
                  decoration: InputDecoration(
                    hintText: 'Search work category...',
                    hintStyle: const TextStyle(color: GawaGoColors.textMuted),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: GawaGoColors.textMuted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: GawaGoColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: GawaGoColors.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (visibleSkills.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 22),
              child: Text(
                'No work category matches that search.',
                style: TextStyle(color: GawaGoColors.textMuted, fontSize: 14),
              ),
            )
          else
            ...visibleSkills.map((skill) {
              final count = widget.jobs
                  .where(
                    (job) =>
                        _normalizeSkill(job.jobType) ==
                            _normalizeSkill(skill) ||
                        _normalizeSkill(job.requiredSkill) ==
                            _normalizeSkill(skill),
                  )
                  .length;
              return _MarketCategoryRow(
                skill: skill,
                openCount: count,
                matches: workerSkills.contains(_normalizeSkill(skill)),
                onTap: () => widget.onOpenJobs(skill),
              );
            }),
        ],
      ),
    );
  }
}

/// One work category inside the market panel. A full-width row rather than
/// a grid cell, so the name, the open-job count and the "View All" action
/// all stay readable at phone width.
class _MarketCategoryRow extends StatelessWidget {
  const _MarketCategoryRow({
    required this.skill,
    required this.openCount,
    required this.matches,
    required this.onTap,
  });

  final String skill;
  final int openCount;
  final bool matches;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: matches ? GawaGoColors.leafTint : GawaGoColors.surfaceMuted,
        border: const Border(top: BorderSide(color: GawaGoColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            skill,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$openCount open ${openCount == 1 ? 'job' : 'jobs'}',
            style: const TextStyle(
              fontSize: 14,
              color: GawaGoColors.textMuted,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(child: _SkillMatchPill(matches: matches)),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: GawaGoColors.ink,
                  side: const BorderSide(color: GawaGoColors.lineStrong),
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: GawaGoColors.fontBody,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                child: const Text('View All'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerJobs extends StatefulWidget {
  const _WorkerJobs({
    required this.repository,
    required this.onChanged,
    this.onApplied,
    this.initialSkill,
  });

  final WorkerRepository repository;
  final VoidCallback onChanged;

  /// An application was sent from this page or a job opened from it: the
  /// other pages refresh, this one keeps its results and filters.
  final VoidCallback? onApplied;
  final String? initialSkill;

  @override
  State<_WorkerJobs> createState() => _WorkerJobsState();
}

class _WorkerJobsState extends State<_WorkerJobs> {
  late String? _skill = widget.initialSkill;
  final _location = TextEditingController();
  late Future<(List<WorkerJob>, WorkerProfile)> _future = _load();

  // AI mode swaps the browsable list for recommender-ranked jobs in place,
  // the way the web "Find Jobs for Me" hero does. Keeping it on this page
  // means the worker never loses the filters they already set.
  bool _aiMode = false;
  bool _mapView = false;
  bool _aiLoading = false;
  String? _aiError;
  List<RecommendedJob> _aiJobs = const [];

  Future<(List<WorkerJob>, WorkerProfile)> _load() async {
    final results = await Future.wait([
      widget.repository.getJobs(skill: _skill, location: _location.text.trim()),
      widget.repository.getProfile(),
    ]);
    return (results[0] as List<WorkerJob>, results[1] as WorkerProfile);
  }

  void _filter() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _runAiMatching() async {
    setState(() {
      _aiMode = true;
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final matches = await widget.repository.getRecommendedJobs();
      if (!mounted) return;
      setState(() {
        _aiJobs = matches;
        _aiLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _aiJobs = const [];
        _aiError = friendlyApiError(error);
        _aiLoading = false;
      });
    }
  }

  void _exitAiMatching() {
    setState(() {
      _aiMode = false;
      _aiJobs = const [];
      _aiError = null;
    });
  }

  Future<void> _openJob(WorkerJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkerJobDetail(
          repository: widget.repository,
          jobId: job.id,
          onChanged: widget.onApplied ?? widget.onChanged,
        ),
      ),
    );
    await _refreshAfterApplying(job.id);
  }

  /// Apply straight from the card, so a worker who already knows the job
  /// does not have to open the detail screen just to reach the button.
  Future<void> _apply(WorkerJob job) async {
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(job.title.isEmpty ? 'Apply to this job' : job.title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Optional note to the household',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Apply Now'),
            ),
          ],
        );
      },
    );
    if (note == null) return;
    try {
      await widget.repository.apply(job.id, note);
      // Refreshes the other pages only: remounting this one threw away the
      // AI results, map view and filters the worker was working through.
      widget.onApplied?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application sent.')));
      await _refreshAfterApplying(job.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  /// After applying, only that job's card changes. In AI mode the ranked
  /// list is kept (re-running the scan takes ~10s) and just that job is
  /// re-read; the browse list is cheap to reload.
  Future<void> _refreshAfterApplying(int jobId) async {
    if (!_aiMode) {
      _filter();
      return;
    }
    try {
      final updated = await widget.repository.getJob(jobId);
      if (!mounted) return;
      setState(() {
        _aiJobs = [
          for (final match in _aiJobs)
            match.job.id == jobId
                ? RecommendedJob(
                    job: updated,
                    aiScore: match.aiScore,
                    skillSimilarity: match.skillSimilarity,
                    distanceKm: match.distanceKm,
                    skillContribution: match.skillContribution,
                    proximityContribution: match.proximityContribution,
                    exactSkillMatch: match.exactSkillMatch,
                  )
                : match,
        ];
      });
    } catch (_) {
      // The card keeps its Apply button; the backend refuses a second
      // application with a clear message.
    }
  }

  void _refreshCurrentMode() {
    if (_aiMode) {
      _runAiMatching();
    } else {
      _filter();
    }
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<WorkerJob>, WorkerProfile)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            // Rebuilding alone re-rendered the same failed future, so Retry
            // did nothing; it has to start a fresh load.
            onRetry: _filter,
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final jobs = snapshot.data!.$1;
        final workerSkills = snapshot.data!.$2.skills
            .map(_normalizeSkill)
            .toSet();
        final sortedJobs = [...jobs]
          ..sort((first, second) {
            final firstMatches = _jobMatchesWorkerSkills(first, workerSkills);
            final secondMatches = _jobMatchesWorkerSkills(second, workerSkills);
            if (firstMatches == secondMatches) return 0;
            return firstMatches ? -1 : 1;
          });
        final viewToggle = ListMapViewToggle(
          mapView: _mapView,
          onChanged: (value) => setState(() => _mapView = value),
        );

        // The map owns drag gestures, so it can't sit inside the scrolling
        // list: Map View fills the screen below the toggle instead.
        if (_mapView && !_aiMode) {
          final profile = snapshot.data!.$2;
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                viewToggle,
                const SizedBox(height: 10),
                const Text(
                  "Every household with an open job is pinned, near or far. "
                  "Tap a pin to see who's hiring.",
                  style: TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: WorkerJobsMap(
                    jobs: sortedJobs,
                    matchesSkills: (job) =>
                        _jobMatchesWorkerSkills(job, workerSkills),
                    distanceLabel: (job) => _distanceLabel(job.distanceKm),
                    onViewDetails: _openJob,
                    onApply: _apply,
                    workerLatitude: profile.latitude,
                    workerLongitude: profile.longitude,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _refreshCurrentMode(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
            children: [
              _WorkerAiHero(
                openJobCount: jobs.length,
                aiMode: _aiMode,
                loading: _aiLoading,
                onFindForMe: _runAiMatching,
                onBackToBrowsing: _exitAiMatching,
              ),
              const SizedBox(height: 16),
              if (!_aiMode) ...[
                _WorkerJobsFilterCard(
                  skill: _skill,
                  location: _location,
                  onSkillChanged: (value) => setState(() => _skill = value),
                  onFilter: _filter,
                ),
                const SizedBox(height: 16),
                viewToggle,
                const SizedBox(height: 12),
                const Text(
                  'Green labels match your skills. Neutral labels are other '
                  'available jobs.',
                  style: TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_aiMode) ...[
                if (_aiLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  const Text(
                    'Ranked for you by skill match and distance. Higher score '
                    '= better fit.',
                    style: TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_aiError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        _aiError!,
                        style: const TextStyle(
                          color: Color(0xFF9A6B1C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (_aiJobs.isEmpty)
                    const AppEmptyState(
                      message:
                          'No matching jobs found within your job radius right '
                          'now.',
                    )
                  else
                    ..._aiJobs.map(
                      (match) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AiMatchBreakdown(
                              skillSharePercent: match.skillSharePercent,
                              exactSkillMatch: match.exactSkillMatch,
                            ),
                            const SizedBox(height: 8),
                            _AvailableJobCard(
                              job: match.job,
                              matchesSkills: match.exactSkillMatch,
                              matchPercent: match.matchPercent,
                              onViewDetails: () => _openJob(match.job),
                              onApply: () => _apply(match.job),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ] else if (sortedJobs.isEmpty)
                const AppEmptyState(
                  message:
                      'There are no household job posts available right now.',
                )
              else
                ...sortedJobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _AvailableJobCard(
                      job: job,
                      matchesSkills: _jobMatchesWorkerSkills(job, workerSkills),
                      onViewDetails: () => _openJob(job),
                      onApply: () => _apply(job),
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

/// The "Let AI find your next job" panel at the top of Find Jobs. In AI
/// mode it collapses to the way back to browsing.
class _WorkerAiHero extends StatelessWidget {
  const _WorkerAiHero({
    required this.openJobCount,
    required this.aiMode,
    required this.loading,
    required this.onFindForMe,
    required this.onBackToBrowsing,
  });

  final int openJobCount;
  final bool aiMode;
  final bool loading;
  final VoidCallback onFindForMe;
  final VoidCallback onBackToBrowsing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'FIND JOBS',
                  style: TextStyle(
                    color: GawaGoColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$openJobCount',
                    style: const TextStyle(
                      fontFamily: GawaGoColors.fontHeading,
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  Text(
                    openJobCount == 1 ? 'open job nearby' : 'open jobs nearby',
                    style: const TextStyle(
                      color: GawaGoColors.mutedText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Let AI find your next job',
            style: TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'We match open jobs near you to your skills, so you spend less '
            'time scrolling and more time earning.',
            style: TextStyle(
              color: GawaGoColors.mutedText,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (aiMode)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onBackToBrowsing,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: GawaGoColors.mutedText),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Browsing'),
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: loading ? null : onFindForMe,
                style: FilledButton.styleFrom(
                  backgroundColor: GawaGoColors.primary,
                  foregroundColor: GawaGoColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: GawaGoColors.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                icon: const Text('*', style: TextStyle(fontSize: 15)),
                label: const Text('Find Jobs for Me'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'or browse manually below',
              style: TextStyle(color: GawaGoColors.mutedText, fontSize: 13.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkerJobsFilterCard extends StatelessWidget {
  const _WorkerJobsFilterCard({
    required this.skill,
    required this.location,
    required this.onSkillChanged,
    required this.onFilter,
  });

  final String? skill;
  final TextEditingController location;
  final ValueChanged<String?> onSkillChanged;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Filter by Job Type'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: skill,
            decoration: _filterFieldDecoration(hintText: 'All Types'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Types')),
              ...gawagoSkills
                  .where((item) => !isOtherSkillChoice(item))
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  ),
            ],
            onChanged: onSkillChanged,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Barangay'),
          const SizedBox(height: 8),
          TextField(
            controller: location,
            onSubmitted: (_) => onFilter(),
            decoration: _filterFieldDecoration(hintText: 'e.g. Lita'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: onFilter,
              style: FilledButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: GawaGoColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: GawaGoColors.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              child: const Text('Filter'),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _filterFieldDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: GawaGoColors.textMuted),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    filled: true,
    fillColor: GawaGoColors.surfaceMuted,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: GawaGoColors.primary, width: 1.4),
    ),
  );
}

/// The small upper-case caption above a field or a card detail row.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: GawaGoColors.textMuted,
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// A job on the worker's Find Jobs list. A dark household panel identifies
/// who posted it, then the white body carries the facts a worker scans
/// before deciding: rate, where, when, how far, and what kind of work.
class _AvailableJobCard extends StatelessWidget {
  const _AvailableJobCard({
    required this.job,
    required this.matchesSkills,
    required this.onViewDetails,
    required this.onApply,
    this.matchPercent,
  });

  final WorkerJob job;
  final bool matchesSkills;
  final VoidCallback onViewDetails;
  final VoidCallback onApply;

  /// Set only in AI mode, where the pill shows the score instead of a plain
  /// matches/does-not-match label.
  final int? matchPercent;

  @override
  Widget build(BuildContext context) {
    final title = job.title.isNotEmpty ? job.title : job.jobType;
    final householdName = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername;
    return Container(
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GawaGoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JobCardHouseholdPanel(
            householdName: householdName,
            verified:
                job.householdVerificationStatus.trim().toLowerCase() ==
                'verified',
            matchesSkills: matchesSkills,
            matchPercent: matchPercent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Untitled job' : title,
                        style: const TextStyle(
                          fontFamily: GawaGoColors.fontHeading,
                          color: GawaGoColors.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _JobCardRate(
                      serviceRate: job.serviceRate,
                      rateTypeLabel: job.rateTypeLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  job.locationLabel.isEmpty
                      ? 'Location not set'
                      : job.locationLabel,
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                _JobCardWhenRow(job: job),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (job.jobType.isNotEmpty)
                      _JobCardChip(
                        label: job.jobType,
                        highlight: matchesSkills,
                      ),
                    if (job.scheduleType.isNotEmpty)
                      _JobCardChip(label: job.scheduleType),
                  ],
                ),
                if (job.jobStartDate.isNotEmpty ||
                    job.jobEndDate.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _jobPeriodLabel(job),
                    style: const TextStyle(
                      color: GawaGoColors.textFaint,
                      fontSize: 13.5,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onViewDetails,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GawaGoColors.ink,
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(
                              color: GawaGoColors.lineStrong,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: GawaGoColors.fontBody,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          child: const Text(
                            'View Details',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: job.canApply ? onApply : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: GawaGoColors.primary,
                            foregroundColor: GawaGoColors.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: GawaGoColors.fontBody,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          child: Text(
                            job.canApply ? 'Apply Now' : 'Applied',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }
}

/// The dark panel at the top of a job card: who posted, whether they are
/// verified, and how the job relates to the worker's skills.
class _JobCardHouseholdPanel extends StatelessWidget {
  const _JobCardHouseholdPanel({
    required this.householdName,
    required this.verified,
    required this.matchesSkills,
    required this.matchPercent,
  });

  final String householdName;
  final bool verified;
  final bool matchesSkills;
  final int? matchPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GawaGoColors.deepGreen,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: verified
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.check,
                            size: 15,
                            color: GawaGoColors.primaryLight,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: GawaGoColors.primaryLight,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              // Flexible so the pill shrinks instead of overflowing the row
              // at phone widths once the household name/verified badge
              // claims its share (F-07).
              Flexible(
                child: matchPercent != null
                    ? _JobCardMatchPill(
                        label: '$matchPercent% match',
                        filled: true,
                      )
                    : _JobCardMatchPill(
                        label: matchesSkills ? 'Matches Skills' : 'Other Job',
                        filled: matchesSkills,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _householdInitials(householdName),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            householdName.isEmpty ? 'Household' : householdName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: GawaGoColors.mutedText, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Filled when the job fits the worker's skills, outlined when it does not --
/// the two states the list hint line explains.
class _JobCardMatchPill extends StatelessWidget {
  const _JobCardMatchPill({required this.label, required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? GawaGoColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: filled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: filled
              ? GawaGoColors.onPrimary
              : Colors.white.withValues(alpha: 0.9),
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _JobCardRate extends StatelessWidget {
  const _JobCardRate({required this.serviceRate, required this.rateTypeLabel});

  final double serviceRate;
  final String rateTypeLabel;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '₱${serviceRate.toStringAsFixed(2)}',
            style: const TextStyle(
              color: GawaGoColors.leafDeep,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(
            text: '/${rateTypeLabel.toLowerCase()}',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.right,
      style: const TextStyle(letterSpacing: 0),
    );
  }
}

/// When the job is, and how far it is. Distance carries its own colour so it
/// reads as the one number a worker compares across cards.
class _JobCardWhenRow extends StatelessWidget {
  const _JobCardWhenRow({required this.job});

  final WorkerJob job;

  @override
  Widget build(BuildContext context) {
    final when = _jobStartDateLabel(job);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: GawaGoColors.textFaint,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: when,
                  style: const TextStyle(
                    color: GawaGoColors.text,
                    fontSize: 14,
                  ),
                ),
                if (job.distanceKm != null)
                  TextSpan(
                    text:
                        '  · ${job.distanceLabel.isNotEmpty ? job.distanceLabel : '${job.distanceKm!.toStringAsFixed(1)} km away'}',
                    style: const TextStyle(
                      color: GawaGoColors.leafDeep,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(letterSpacing: 0, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _JobCardChip extends StatelessWidget {
  const _JobCardChip({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? GawaGoColors.leafTint : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlight
              ? GawaGoColors.primary.withValues(alpha: 0.55)
              : GawaGoColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight ? GawaGoColors.leafDeep : GawaGoColors.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// "Santos Residence" -> "SR". Falls back to the first two characters when
/// the name is a single word, so a username still reads as a monogram.
String _householdInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'H';
  if (parts.length == 1) {
    final single = parts.first;
    return (single.length == 1 ? single : single.substring(0, 2)).toUpperCase();
  }
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

String _jobStartDateLabel(WorkerJob job) {
  if (job.jobStartDate.isNotEmpty) return _jobDate(job.jobStartDate);
  return _scheduleLabel(job.schedule);
}

String _jobPeriodLabel(WorkerJob job) {
  final start = job.jobStartDate.isEmpty ? 'Not set' : job.jobStartDate;
  final end = job.jobEndDate.isEmpty ? '' : ' to ${job.jobEndDate}';
  final days = job.estimatedWorkingDays == null
      ? ''
      : ' (${job.estimatedWorkingDays} working '
            '${job.estimatedWorkingDays == 1 ? 'day' : 'days'})';
  return '$start$end$days';
}

class _SkillMatchPill extends StatelessWidget {
  const _SkillMatchPill({required this.matches});

  final bool matches;

  @override
  Widget build(BuildContext context) {
    final color = matches ? GawaGoColors.leafDeep : GawaGoColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: matches ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        matches ? 'Matches your skills' : 'Does not match skills',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _WorkerJobDetail extends StatefulWidget {
  const _WorkerJobDetail({
    required this.repository,
    required this.jobId,
    required this.onChanged,
  });

  final WorkerRepository repository;
  final int jobId;
  final VoidCallback onChanged;

  @override
  State<_WorkerJobDetail> createState() => _WorkerJobDetailState();
}

class _WorkerJobDetailState extends State<_WorkerJobDetail> {
  late Future<(WorkerJob, WorkerProfile)> _future = _load();
  bool _busy = false;

  Future<(WorkerJob, WorkerProfile)> _load() async {
    final results = await Future.wait([
      widget.repository.getJob(widget.jobId),
      widget.repository.getProfile(),
    ]);
    return (results[0] as WorkerJob, results[1] as WorkerProfile);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
      _message('Action completed.');
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<String?> _askNote(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Optional note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    // The TextField stays mounted through the dialog's close animation, so
    // disposing the controller immediately could hit it mid-transition
    // ("used after being disposed"). Deferring past the animation avoids
    // that without blocking this function's return (F-27).
    Future.delayed(const Duration(milliseconds: 300), controller.dispose);
    return result;
  }

  Future<void> _review(WorkerJob job) async {
    double rating = 5;
    final feedback = TextEditingController();
    // Optional 1-5 detail scores mirroring the web review form; null means
    // "not rated" and is simply omitted from the request.
    final metrics = <String, int?>{
      'quality_of_work': null,
      'punctuality': null,
      'communication': null,
      'professionalism': null,
    };
    const metricLabels = {
      'quality_of_work': 'Quality of Work',
      'punctuality': 'Punctuality',
      'communication': 'Communication',
      'professionalism': 'Professionalism',
    };
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Leave Feedback for Household'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<double>(
                  initialValue: rating,
                  decoration: const InputDecoration(
                    labelText: 'Overall rating',
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.toDouble(),
                          child: Text('$value star${value == 1 ? '' : 's'}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => rating = value ?? 5),
                ),
                for (final field in metricLabels.keys)
                  DropdownButtonFormField<int?>(
                    initialValue: metrics[field],
                    decoration: InputDecoration(labelText: metricLabels[field]),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Not rated'),
                      ),
                      ...[1, 2, 3, 4, 5].map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => metrics[field] = value),
                  ),
                TextField(
                  controller: feedback,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Feedback'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (submit == true) {
      await _run(
        () => widget.repository.reviewHousehold(
          job,
          rating: rating,
          feedback: feedback.text.trim(),
          qualityOfWork: metrics['quality_of_work'],
          punctuality: metrics['punctuality'],
          communication: metrics['communication'],
          professionalism: metrics['professionalism'],
        ),
      );
    }
    feedback.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedDetailScaffold(
      title: 'Job Details',
      child: FutureBuilder<(WorkerJob, WorkerProfile)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorState(error: snapshot.error, onRetry: _reload);
          }
          if (!snapshot.hasData) return const AppLoadingState();
          final (job, profile) = snapshot.data!;
          final workerPoint =
              profile.latitude == null || profile.longitude == null
              ? null
              : LatLng(profile.latitude!, profile.longitude!);
          final jobPoint = job.latitude == null || job.longitude == null
              ? null
              : LatLng(job.latitude!, job.longitude!);
          final actions = <Widget>[
            if (job.canApply)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _askNote('Apply to this job');
                        if (note != null) {
                          await _run(
                            () => widget.repository.apply(job.id, note),
                          );
                        }
                      },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Apply Now'),
              ),
            if (job.canAcceptHireRequest)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.decideHireRequest(
                          job.application!.id,
                          'accept',
                        ),
                      ),
                icon: const Icon(Icons.check),
                label: const Text('Accept Request'),
              ),
            if (job.canAcceptHireRequest)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.decideHireRequest(
                          job.application!.id,
                          'reject',
                        ),
                      ),
                icon: const Icon(Icons.close),
                label: const Text('Reject Request'),
              ),
            if (job.canRequestCompletion)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _askNote('Request completion');
                        if (note != null) {
                          await _run(
                            () => widget.repository.requestCompletion(
                              job.id,
                              note,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.task_alt),
                label: const Text('Mark Work as Done'),
              ),
            if (job.canReview)
              FilledButton.icon(
                onPressed: _busy ? null : () => _review(job),
                icon: const Icon(Icons.star_outline),
                label: const Text('Leave Feedback for Household'),
              ),
            if (job.application != null)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final submitted = await showReportIssueDialog(
                          context: context,
                          jobId: job.id,
                          jobTitle: job.title,
                          isHousehold: false,
                        );
                        if (submitted && mounted) {
                          _message(
                            'Report submitted. Our admin team will review it.',
                          );
                        }
                      },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report an Issue'),
              ),
          ];
          final applied = job.application != null;
          final notice = job.canAcceptHireRequest
              ? 'This household sent you a hire request. Review the job '
                    'details before accepting or rejecting.'
              : (!job.canApply && !applied)
              ? 'Applications are unavailable for this job right now.'
              : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
            children: [
              _WorkerHouseholdProfileCard(job: job),
              const SizedBox(height: 14),
              _WorkerJobDetailsCard(
                job: job,
                busy: _busy,
                actions: actions,
                backLabel: job.canAcceptHireRequest
                    ? 'Back to Notifications'
                    : 'Back to Find Jobs',
                notice: notice,
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),
              _WorkerJobDistanceCard(
                job: job,
                workerPoint: workerPoint,
                jobPoint: jobPoint,
                workerLocationLabel: profile.locationLabel,
              ),
              const SizedBox(height: 14),
              _WorkerPhotosCard(images: job.images),
              if (applied) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    status: job.application!.status,
                    prefix: 'Application',
                    label: job.application!.statusLabel.isNotEmpty
                        ? job.application!.statusLabel
                        : applicationStatusLabel(job.application!.status),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One label/value line in the job info table. The value is upper-cased and
/// right-aligned, matching the definition list the web job detail renders.
class _WorkerDetailRow extends StatelessWidget {
  const _WorkerDetailRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: GawaGoColors.border)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 14.5,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              (value.trim().isEmpty ? 'Not set' : value).toUpperCase(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The household behind the posting. Contact details are deliberately absent
/// until the worker is hired -- the serializer withholds them, so the card
/// says so rather than rendering blanks.
class _WorkerHouseholdProfileCard extends StatelessWidget {
  const _WorkerHouseholdProfileCard({required this.job});

  final WorkerJob job;

  @override
  Widget build(BuildContext context) {
    final name = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername;
    final application = job.application;
    final phone = application?.householdPhone ?? '';
    final email = application?.householdEmail ?? '';
    final hasContact = phone.isNotEmpty || email.isNotEmpty;
    final contactLine = hasContact
        ? [
            if (phone.isNotEmpty) '+63${sanitizePhilippinesPhone(phone)}',
            if (email.isNotEmpty) email,
          ].join(' | ')
        : 'Contact details become available after you are hired.';

    return ProfileSection(
      title: 'Household Profile',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: GawaGoColors.border,
            child: Text(
              _initial(name),
              style: const TextStyle(
                fontFamily: GawaGoColors.fontHeading,
                color: GawaGoColors.textMuted,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Household' : name,
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: GawaGoColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  job.locationLabel.isEmpty
                      ? 'Location not set'
                      : job.locationLabel,
                  style: const TextStyle(
                    color: GawaGoColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  contactLine,
                  style: TextStyle(
                    color: hasContact
                        ? GawaGoColors.ink
                        : GawaGoColors.textFaint,
                    fontSize: 13.5,
                    height: 1.35,
                    fontStyle: hasContact ? FontStyle.normal : FontStyle.italic,
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

class _WorkerJobDetailsCard extends StatelessWidget {
  const _WorkerJobDetailsCard({
    required this.job,
    required this.busy,
    required this.actions,
    required this.onBack,
    required this.backLabel,
    required this.notice,
  });

  final WorkerJob job;
  final bool busy;
  final List<Widget> actions;
  final VoidCallback onBack;
  final String backLabel;

  /// The contextual banner the web shows under the actions: a hire-request
  /// prompt, or why applying is unavailable.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final title = job.title.isNotEmpty ? job.title : job.jobType;
    return ProfileSection(
      title: title.isEmpty ? 'Job Details' : title,
      action: _WorkerStatusPill(text: statusText(job.statusLabel, job.status)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkerDetailRow(
            label: 'Service',
            value: job.jobType.isEmpty ? job.requiredSkill : job.jobType,
          ),
          _WorkerDetailRow(
            label: 'Schedule',
            value: job.scheduleType.isEmpty
                ? _scheduleLabel(job.schedule)
                : job.scheduleType,
          ),
          if (job.jobStartDate.isNotEmpty || job.jobEndDate.isNotEmpty)
            _WorkerDetailRow(label: 'Job Period', value: _jobPeriodLabel(job)),
          if (job.estimatedWorkingDays != null)
            _WorkerDetailRow(
              label: 'Working Days',
              value:
                  '${job.estimatedWorkingDays} '
                  '${job.estimatedWorkingDays == 1 ? 'day' : 'days'}',
            ),
          _WorkerDetailRow(
            label: 'Needed',
            value: '${job.hiredCount}/${job.workerSlots} hired',
          ),
          _WorkerDetailRow(
            label: 'Rate',
            value:
                'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}',
          ),
          _WorkerDetailRow(
            label: 'Location',
            value: job.locationLabel,
            last: true,
          ),
          const Divider(height: 1, color: GawaGoColors.border),
          const SizedBox(height: 14),
          const Text(
            'Description',
            style: TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 14,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            job.description.trim().isEmpty
                ? 'No description provided.'
                : job.description.trim(),
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 15.5,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: busy ? null : onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: GawaGoColors.ink,
                side: const BorderSide(color: GawaGoColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: GawaGoColors.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              child: Text(backLabel),
            ),
          ),
          ...actions.map(
            (action) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(height: 50, child: action),
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF4E3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEBD9B4)),
              ),
              child: Text(
                notice!,
                style: const TextStyle(
                  color: Color(0xFF7A5B12),
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The job's real status in the section header, rather than a hardcoded
/// "Open" that stayed put after a job was filled or cancelled.
class _WorkerStatusPill extends StatelessWidget {
  const _WorkerStatusPill({required this.text});

  /// Already-presentable text. Callers that hold a raw backend status run it
  /// through formatStatus first; a distance label must not go through it,
  /// since that would title-case "0.48 km away" into "0.48 Km Away".
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Worker's registered location to the job site, with the distance in the
/// section header the way the web puts it in the card head.
class _WorkerJobDistanceCard extends StatelessWidget {
  const _WorkerJobDistanceCard({
    required this.job,
    required this.workerPoint,
    required this.jobPoint,
    required this.workerLocationLabel,
  });

  final WorkerJob job;
  final LatLng? workerPoint;
  final LatLng? jobPoint;
  final String workerLocationLabel;

  @override
  Widget build(BuildContext context) {
    return ProfileSection(
      title: 'Distance & Locations',
      action: _WorkerStatusPill(
        text: job.distanceLabel.isNotEmpty
            ? job.distanceLabel
            : (job.distanceKm == null
                  ? 'Distance unavailable'
                  : '${job.distanceKm!.toStringAsFixed(2)} km away'),
      ),
      child: LocationRouteMap(
        embedded: true,
        start: workerPoint,
        end: jobPoint,
        startLabel: 'Worker',
        endLabel: 'Job',
        startLocationLabel: workerLocationLabel,
        endLocationLabel: job.locationLabel,
        routePoints: job.routePoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList(),
        roadDistanceKm: job.distanceKm,
      ),
    );
  }
}

class _WorkerPhotosCard extends StatelessWidget {
  const _WorkerPhotosCard({required this.images});

  final List<JobImage> images;

  @override
  Widget build(BuildContext context) {
    return ProfileSection(
      title: 'Photos of Work Area',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (images.isEmpty)
            const SectionEmptyText('No photos uploaded yet.')
          else ...[
            const Text(
              'These photos help workers see the area before applying.',
              style: TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            JobImageGallery(images: images),
          ],
        ],
      ),
    );
  }
}

class _WorkerMyReports extends StatefulWidget {
  const _WorkerMyReports({required this.repository});

  final WorkerRepository repository;

  @override
  State<_WorkerMyReports> createState() => _WorkerMyReportsState();
}

class _WorkerMyReportsState extends State<_WorkerMyReports> {
  late final Future<WorkerProfile> _future = widget.repository.getProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: _future,
      builder: (context, snapshot) {
        return MyComplaintsView(currentUsername: snapshot.data?.username);
      },
    );
  }
}

class _WorkerApplications extends StatefulWidget {
  const _WorkerApplications({required this.repository});

  final WorkerRepository repository;

  @override
  State<_WorkerApplications> createState() => _WorkerApplicationsState();
}

class _WorkerApplicationsState extends State<_WorkerApplications> {
  String? _statusFilter;
  late Future<List<WorkerApplication>> _future = widget.repository
      .getApplications();

  void _reload() {
    setState(() {
      _future = widget.repository.getApplications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkerApplication>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final applications = snapshot.data!;
        final visible = _statusFilter == null
            ? applications
            : applications
                  .where(
                    (item) =>
                        _workerApplicationDisplayStatus(
                          item,
                        ).trim().toLowerCase() ==
                        _statusFilter!.trim().toLowerCase(),
                  )
                  .toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Applications',
                            style: TextStyle(
                              fontFamily: GawaGoColors.fontHeading,
                              color: GawaGoColors.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  isExpanded: true,
                                  initialValue: _statusFilter,
                                  decoration: _filterFieldDecoration(
                                    hintText: 'All Status',
                                  ),
                                  items: const [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Status'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'Pending',
                                      child: Text('Pending'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'In Progress',
                                      child: Text('In Progress'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'Awaiting confirmation',
                                      child: Text('Awaiting Confirmation'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'Completed',
                                      child: Text('Completed'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _statusFilter = value),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 48,
                                child: FilledButton(
                                  onPressed: _reload,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: GawaGoColors.primary,
                                    foregroundColor: GawaGoColors.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    textStyle: const TextStyle(
                                      fontFamily: GawaGoColors.fontBody,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  child: const Text('Filter'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        child: Text(
                          applications.isEmpty
                              ? 'You have not applied to any jobs yet.'
                              : 'No applications found for this status.',
                          style: const TextStyle(
                            color: GawaGoColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      )
                    else
                      ...visible.map(
                        (item) => _WorkerApplicationRow(application: item),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One application inside the My Applications card: title and live status on
/// the header line, then the facts a worker checks before following up.
class _WorkerApplicationRow extends StatelessWidget {
  const _WorkerApplicationRow({required this.application});

  final WorkerApplication application;

  @override
  Widget build(BuildContext context) {
    final status = _workerApplicationDisplayStatus(application);
    final stage = _workerApplicationStage(application);
    final household = application.householdName.isNotEmpty
        ? application.householdName
        : application.householdUsername.isNotEmpty
        ? application.householdUsername
        : 'Household';
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: GawaGoColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  application.jobTitle.isEmpty
                      ? application.jobType
                      : application.jobTitle,
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: GawaGoColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                status,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _applicationStatusColor(stage),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            application.jobType.isEmpty ? 'Not set' : application.jobType,
            style: const TextStyle(
              color: GawaGoColors.leafDeep,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ApplicationFact(label: 'Household', value: household),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ApplicationFact(
                  label: 'Schedule',
                  value: _workerApplicationSchedule(application),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ApplicationFact(
                  label: 'Location',
                  value: application.locationLabel.isEmpty
                      ? 'Not set'
                      : application.locationLabel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ApplicationFact(
                  label: 'Rate',
                  value:
                      'PHP ${application.serviceRate.toStringAsFixed(2)} / ${application.rateTypeLabel}',
                ),
              ),
            ],
          ),
          if (application.distanceKm != null) ...[
            const SizedBox(height: 8),
            _ApplicationFact(
              label: 'Distance',
              value: application.distanceLabel.isNotEmpty
                  ? application.distanceLabel
                  : '${application.distanceKm!.toStringAsFixed(1)} km away',
            ),
          ],
          if (application.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _ApplicationFact(
              label: 'Your note',
              value: application.note.trim(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Applied ${formatLocalDateTime(application.appliedAt)}',
            style: const TextStyle(
              color: GawaGoColors.textFaint,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationFact extends StatelessWidget {
  const _ApplicationFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(
        color: GawaGoColors.ink,
        fontSize: 13.5,
        height: 1.35,
        letterSpacing: 0,
      ),
    );
  }
}

/// Status wording carries the colour on this screen -- there is no pill --
/// so the three states a worker acts on stay distinguishable at a glance.
/// Keyed by the canonical stage (apps/jobs/statuses.py), not the display
/// label, so it doesn't depend on the exact wording of that label.
Color _applicationStatusColor(String stage) {
  return switch (stage.toLowerCase()) {
    'completed' || 'in_progress' => GawaGoColors.leafDeep,
    'awaiting_confirmation' => GawaGoColors.leafDeep,
    'rejected' || 'cancelled' => GawaGoColors.danger,
    _ => const Color(0xFFB07B12),
  };
}

/// Prefers the backend's status_label (apps/jobs/statuses.py), which is
/// computed from both the application and job status together -- the same
/// vocabulary the web client renders. Older cached records without that
/// field fall back to the local mapping.
String _workerApplicationDisplayStatus(WorkerApplication item) {
  if (item.statusLabel.isNotEmpty) return item.statusLabel;
  final jobStatus = item.jobStatus.trim().toLowerCase();
  if (jobStatus == 'completion_requested') {
    return 'Waiting for Household Confirmation';
  }
  return applicationStatusLabel(item.status.isEmpty ? 'pending' : item.status);
}

String _workerApplicationStage(WorkerApplication item) {
  if (item.statusStage.isNotEmpty) return item.statusStage;
  final jobStatus = item.jobStatus.trim().toLowerCase();
  if (jobStatus == 'completion_requested') return 'awaiting_confirmation';
  return item.status.trim().toLowerCase();
}

/// The work a worker is hired for, split from their finished history --
/// the mobile counterpart to the web "My Jobs" tab. Was previously only
/// reachable via "Mark Work as Done" buried in a job's own detail screen;
/// this gives it a dedicated home matching web.
class _WorkerMyJobs extends StatefulWidget {
  const _WorkerMyJobs({required this.repository, required this.onChanged});

  final WorkerRepository repository;
  final VoidCallback onChanged;

  @override
  State<_WorkerMyJobs> createState() => _WorkerMyJobsState();
}

class _WorkerMyJobsState extends State<_WorkerMyJobs> {
  late Future<(List<WorkerApplication>, List<GawaGoReview>)> _future = _load();
  bool _busy = false;

  Future<(List<WorkerApplication>, List<GawaGoReview>)> _load() async {
    final results = await Future.wait([
      widget.repository.getApplications(),
      widget.repository.getReceivedReviews(),
    ]);
    return (
      results[0] as List<WorkerApplication>,
      results[1] as List<GawaGoReview>,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _markComplete(WorkerApplication job) async {
    if (_busy) return;
    final household = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername.isNotEmpty
        ? job.householdUsername
        : 'the household';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark as complete'),
        content: Text(
          'This lets $household know the job is finished, so they can review and confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.repository.requestCompletion(
        job.jobId,
        'I have completed the service today.',
      );
      // This page lives inside the drawer's IndexedStack, keyed off a
      // refresh counter -- widget.onChanged() bumps that counter and
      // recreates this widget on the spot, so anything after it would run
      // on an already-disposed State. Finish local feedback first; the
      // fresh instance onChanged() spawns will reload this same data anyway.
      if (mounted) {
        _message('Marked complete. Waiting for $household to confirm.');
      }
      widget.onChanged();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<WorkerApplication>, List<GawaGoReview>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final (applications, reviews) = snapshot.data!;

        // The application stays Hired while the job runs, including once
        // completion has been requested, so job stage is what separates
        // active work from finished history.
        final inProgress = applications.where((item) {
          final stage = _workerApplicationStage(item);
          return stage == 'in_progress' || stage == 'awaiting_confirmation';
        }).toList();
        final completed = applications
            .where((item) => _workerApplicationStage(item) == 'completed')
            .toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
            children: [
              Text(
                'In Progress · ${inProgress.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4,
                  color: GawaGoColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              if (inProgress.isEmpty)
                const _WorkerMyJobsEmptyCard(
                  message: 'No active jobs right now.',
                )
              else
                for (final job in inProgress) ...[
                  _WorkerInProgressJobCard(
                    job: job,
                    busy: _busy,
                    onMarkComplete: () => _markComplete(job),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 20),
              Text(
                'Completed · ${completed.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4,
                  color: GawaGoColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              if (completed.isEmpty)
                const _WorkerMyJobsEmptyCard(
                  message: 'Your finished jobs will appear here.',
                )
              else
                for (final job in completed) ...[
                  _WorkerCompletedJobCard(
                    job: job,
                    review: reviews
                        .where((r) => r.jobId == job.jobId)
                        .firstOrNull,
                    // The detail page holds "Leave Feedback for Household"
                    // and "Report an issue"; without this they were only
                    // reachable from a notification.
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _WorkerJobDetail(
                          repository: widget.repository,
                          jobId: job.jobId,
                          onChanged: _reload,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _WorkerMyJobsEmptyCard extends StatelessWidget {
  const _WorkerMyJobsEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 14),
      ),
    );
  }
}

class _WorkerInProgressJobCard extends StatelessWidget {
  const _WorkerInProgressJobCard({
    required this.job,
    required this.busy,
    required this.onMarkComplete,
  });

  final WorkerApplication job;
  final bool busy;
  final VoidCallback onMarkComplete;

  @override
  Widget build(BuildContext context) {
    final household = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername.isNotEmpty
        ? job.householdUsername
        : 'Household';
    final awaitingConfirmation =
        _workerApplicationStage(job) == 'awaiting_confirmation';
    // The backend refuses completion before the start date (a review must
    // follow work that happened), so the button waits for it too.
    final startDate = DateTime.tryParse(job.jobStartDate);
    final now = DateTime.now();
    final notStarted =
        startDate != null &&
        DateTime(now.year, now.month, now.day).isBefore(startDate);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: awaitingConfirmation
              ? GawaGoColors.primary
              : GawaGoColors.border,
          width: awaitingConfirmation ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.jobTitle.isEmpty ? job.jobType : job.jobTitle,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _workerApplicationDisplayStatus(job),
            style: TextStyle(
              color: awaitingConfirmation
                  ? GawaGoColors.leafDeep
                  : const Color(0xFFB07B12),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            household,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            job.locationLabel.isEmpty ? 'Location not set' : job.locationLabel,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}',
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (awaitingConfirmation)
            Text(
              'Marked complete — waiting for $household to confirm.',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (notStarted)
            Text(
              'You can mark this job complete once it starts on ${job.jobStartDate}.',
              key: const ValueKey('worker-job-not-started'),
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onMarkComplete,
                icon: const Icon(Icons.task_alt),
                label: const Text('Mark job as complete'),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkerCompletedJobCard extends StatelessWidget {
  const _WorkerCompletedJobCard({
    required this.job,
    required this.review,
    required this.onOpen,
  });

  final WorkerApplication job;
  final GawaGoReview? review;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final household = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername.isNotEmpty
        ? job.householdUsername
        : 'Household';
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GawaGoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GawaGoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.jobTitle.isEmpty ? job.jobType : job.jobTitle,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Completed',
              style: TextStyle(
                color: GawaGoColors.leafDeep,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              household,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              review?.rating != null
                  ? 'Rating received: ${review!.rating!.toStringAsFixed(1)} / 5'
                  : 'No rating yet',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _workerApplicationSchedule(WorkerApplication item) {
  if (item.jobStartDate.isNotEmpty) return _jobDate(item.jobStartDate);
  return _scheduleLabel(item.jobSchedule);
}

class _WorkerProfile extends StatefulWidget {
  const _WorkerProfile({
    required this.repository,
    required this.onSaved,
    this.onSkillsChanged,
  });

  final WorkerRepository repository;
  final VoidCallback onSaved;

  /// A portfolio skill was added or removed. That changes the skills
  /// matching uses, so the pages built from them need a refresh -- without
  /// remounting this page and losing the edit in progress.
  final VoidCallback? onSkillsChanged;

  @override
  State<_WorkerProfile> createState() => _WorkerProfileState();
}

class _WorkerProfileState extends State<_WorkerProfile> {
  late Future<WorkerProfile> _future = widget.repository.getProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () {
              setState(() {
                _future = widget.repository.getProfile();
              });
            },
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        return _ProfileForm(
          profile: snapshot.data!,
          repository: widget.repository,
          onSkillsChanged: widget.onSkillsChanged,
          onSaved: () {
            widget.onSaved();
            setState(() {
              _future = widget.repository.getProfile();
            });
          },
        );
      },
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({
    required this.profile,
    required this.repository,
    required this.onSaved,
    this.onSkillsChanged,
  });

  final WorkerProfile profile;
  final WorkerRepository repository;
  final VoidCallback onSaved;
  final VoidCallback? onSkillsChanged;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final _firstName = TextEditingController(text: widget.profile.firstName);
  late final _lastName = TextEditingController(text: widget.profile.lastName);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _hourly = TextEditingController(
    text: widget.profile.hourlyRate?.toString() ?? '',
  );
  late final _daily = TextEditingController(
    text: widget.profile.dailyRate?.toString() ?? '',
  );
  late final _experience = TextEditingController(
    text: widget.profile.yearsExperience.toString(),
  );
  late final _location = TextEditingController(
    text: widget.profile.locationLabel,
  );
  late LatLng? _profilePin =
      widget.profile.latitude == null || widget.profile.longitude == null
      ? null
      : LatLng(widget.profile.latitude!, widget.profile.longitude!);
  late final Set<String> _skills = widget.profile.skills.toSet();

  /// The skill list as last saved. Portfolio Add/Remove change it on the
  /// backend straight away, so they are refused while the chips above hold
  /// unsaved changes -- otherwise the two editors fought over the 3-skill
  /// limit and a later Save undid the portfolio change.
  late Set<String> _savedSkills = widget.profile.skills.toSet();

  bool get _skillChipsUnsaved =>
      _skills.length != _savedSkills.length ||
      !_skills.containsAll(_savedSkills);
  late final List<AvailabilityWindow> _availabilityWindows = [
    ...widget.profile.availabilityWindows,
  ];
  String? _photoPath;
  bool _saving = false;

  /// The page reads first and edits on request, like the web profile: the
  /// fields stay visible but locked until "Edit Profile" is pressed.
  bool _editing = false;

  late Future<WorkerPortfolio> _portfolio = widget.repository.getPortfolio();
  late final Future<List<WorkerJob>> _history = widget.repository
      .getEmploymentHistory(widget.profile.userId);

  void _reloadPortfolio() {
    setState(() {
      _portfolio = widget.repository.getPortfolio();
    });
  }

  Future<void> _pickPhoto() async {
    const group = XTypeGroup(
      label: 'Profile photo',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _photoPath = file.path);
  }

  /// Leaving edit mode without saving puts every field back to what is
  /// saved. "Done Editing" used to keep the unsaved values on screen, where
  /// they looked saved but were gone on the next reload. (Portfolio items
  /// added meanwhile are saved immediately and stay.)
  void _cancelEditing() {
    final profile = widget.profile;
    setState(() {
      _firstName.text = profile.firstName;
      _lastName.text = profile.lastName;
      _email.text = profile.email;
      _phone.text = profile.phone;
      _bio.text = profile.bio;
      _hourly.text = profile.hourlyRate?.toString() ?? '';
      _daily.text = profile.dailyRate?.toString() ?? '';
      _experience.text = profile.yearsExperience.toString();
      _location.text = profile.locationLabel;
      _profilePin = profile.latitude == null || profile.longitude == null
          ? null
          : LatLng(profile.latitude!, profile.longitude!);
      _skills
        ..clear()
        ..addAll(_savedSkills);
      _availabilityWindows
        ..clear()
        ..addAll(profile.availabilityWindows);
      _photoPath = null;
      _editing = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_profilePin == null) {
      _message('Select your exact Tayabas location on the map.');
      return;
    }
    if ((double.tryParse(_hourly.text) ?? 0) <= 0 &&
        (double.tryParse(_daily.text) ?? 0) <= 0) {
      _message('Enter an hourly or daily service rate.');
      return;
    }
    // "Other" is never saved as a skill (an older profile may still hold it).
    final skills = resolveWorkerSkills(_skills, '');
    if (skills.isEmpty) {
      _message('Choose at least one skill.');
      return;
    }
    if (_availabilityWindows.any((item) => item.startTime == item.endTime)) {
      _message('Availability start and end time must be different.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _email.text.trim(),
        'phone': sanitizePhilippinesPhone(_phone.text),
        'bio': _bio.text.trim(),
        'hourly_rate': _hourly.text.trim(),
        'daily_rate': _daily.text.trim(),
        'years_experience': int.tryParse(_experience.text) ?? 0,
        'location_label': _location.text.trim(),
        'latitude': _coordinateForApi(_profilePin!.latitude),
        'longitude': _coordinateForApi(_profilePin!.longitude),
        'skills': skills,
      }, profilePhotoPath: _photoPath);
      await widget.repository.saveAvailabilityWindows(_availabilityWindows);
      _skills
        ..clear()
        ..addAll(skills);
      _savedSkills = _skills.toSet();
      if (mounted) {
        setState(() => _editing = false);
        _message('Profile and availability saved.');
        // Profile skills and portfolio skills are one list on the backend.
        _reloadPortfolio();
      }
      widget.onSaved();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addDateAvailability() async {
    DateTime date = DateTime.now();
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add date availability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Date'),
                trailing: Text(_dateValue(date)),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (value != null) setDialogState(() => date = value);
                },
              ),
              ListTile(
                title: const Text('Start time'),
                trailing: Text(start.format(context)),
                onTap: () async {
                  final value = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (value != null) setDialogState(() => start = value);
                },
              ),
              ListTile(
                title: const Text('End time'),
                trailing: Text(end.format(context)),
                onTap: () async {
                  final value = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (value != null) setDialogState(() => end = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (added == true) {
      setState(() {
        _availabilityWindows.add(
          AvailabilityWindow(
            date: _dateValue(date),
            startTime: _timeValue(start),
            endTime: _timeValue(end),
          ),
        );
      });
    }
  }

  // ---- Portfolio editing ----

  Future<void> _runPortfolioAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (!mounted) return;
      _message(successMessage);
      _reloadPortfolio();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    }
  }

  Future<void> _addTypedSkillChip() async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a skill not listed'),
        content: TextField(
          key: const ValueKey('profile-typed-skill-field'),
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Skill name',
            hintText: 'e.g. Masonry',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (typed == null || !mounted) return;
    final names = resolveWorkerSkills([gawagoOtherSkill], typed);
    if (names.isEmpty) {
      _message('Type the name of the skill.');
      return;
    }
    // A typed catalog name ticks that chip instead of adding a copy.
    final catalogName = gawagoSkills.firstWhere(
      (skill) => skill.toLowerCase() == names.first.toLowerCase(),
      orElse: () => names.first,
    );
    if (_skills.any(
      (skill) => skill.toLowerCase() == catalogName.toLowerCase(),
    )) {
      _message('That skill is already listed.');
      return;
    }
    setState(() => _skills.add(catalogName));
  }

  Future<void> _addPortfolioSkill(List<PortfolioSkill> existing) async {
    if (_skillChipsUnsaved) {
      _message('Save your skill changes first, then add a portfolio skill.');
      return;
    }
    if (_skills.length >= maxWorkerSkills) {
      _message(
        'You can list at most $maxWorkerSkills skills. Remove one first.',
      );
      return;
    }
    final taken = {
      ...existing.map((item) => item.skillName.toLowerCase()),
      ..._skills.map((item) => item.toLowerCase()),
    };
    // "Other" stays last and opens a text box: the word itself is never a
    // skill (the backend refuses it).
    final available = gawagoSkills
        .where(
          (skill) =>
              isOtherSkillChoice(skill) || !taken.contains(skill.toLowerCase()),
        )
        .toList();
    final typedSkill = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        String skill = available.first;
        String proficiency = PortfolioSkill.proficiencyOptions.first;
        String? typedError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add skill'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: skill,
                  decoration: const InputDecoration(labelText: 'Skill'),
                  items: available
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            isOtherSkillChoice(item) ? 'Other (type it)' : item,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => skill = value ?? skill),
                ),
                if (isOtherSkillChoice(skill)) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('portfolio-custom-skill'),
                    controller: typedSkill,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Skill name',
                      hintText: 'e.g. Masonry',
                      errorText: typedError,
                      counterText: '',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: proficiency,
                  decoration: const InputDecoration(labelText: 'Proficiency'),
                  items: PortfolioSkill.proficiencyOptions
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            '${item[0].toUpperCase()}${item.substring(1)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => proficiency = value ?? proficiency),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!isOtherSkillChoice(skill)) {
                    Navigator.pop(dialogContext, (skill, proficiency));
                    return;
                  }
                  final typed = resolveWorkerSkills([
                    gawagoOtherSkill,
                  ], typedSkill.text);
                  if (typed.isEmpty) {
                    setDialogState(
                      () => typedError = 'Type the name of the skill.',
                    );
                    return;
                  }
                  if (taken.contains(typed.first.toLowerCase())) {
                    setDialogState(
                      () => typedError = 'That skill is already listed.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, (typed.first, proficiency));
                },
                child: const Text('Add Skill'),
              ),
            ],
          ),
        );
      },
    );
    typedSkill.dispose();
    if (result == null) return;
    await _runPortfolioAction(() async {
      await widget.repository.addPortfolioSkill(
        skillName: result.$1,
        proficiency: result.$2,
      );
      // The backend adds it to the profile list too; keep the form's copy in
      // step so a later Save doesn't drop it again.
      _skills.add(result.$1);
      _savedSkills.add(result.$1);
      widget.onSkillsChanged?.call();
    }, 'Skill added.');
  }

  Future<void> _addCertification() async {
    final result = await showDialog<_CertificationDraft>(
      context: context,
      builder: (dialogContext) => const _CertificationDialog(),
    );
    if (result == null) return;
    await _runPortfolioAction(
      () => widget.repository.addCertification(
        certificateName: result.name,
        certificateType: result.type,
        issuer: result.issuer,
        issueDate: result.issueDate,
        expiryDate: result.expiryDate,
        filePath: result.filePath,
      ),
      'Certificate submitted for review.',
    );
  }

  Future<void> _addWorkSample() async {
    final result = await showDialog<_WorkSampleDraft>(
      context: context,
      builder: (dialogContext) => const _WorkSampleDialog(),
    );
    if (result == null) return;
    await _runPortfolioAction(
      () => widget.repository.addWorkSample(
        title: result.title,
        description: result.description,
        beforePath: result.beforePath!,
        afterPath: result.afterPath!,
      ),
      'Work sample added.',
    );
  }

  Future<void> _editWorkSample(WorkSample sample) async {
    final result = await showDialog<_WorkSampleDraft>(
      context: context,
      builder: (dialogContext) => _WorkSampleDialog(existing: sample),
    );
    if (result == null) return;
    await _runPortfolioAction(
      () => widget.repository.updateWorkSample(
        sample.id,
        title: result.title,
        description: result.description,
        beforePath: result.beforePath,
        afterPath: result.afterPath,
      ),
      'Work sample updated.',
    );
  }

  Future<bool> _confirmDelete(String what) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $what?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
      children: [
        _WorkerProfileSummary(
          profile: widget.profile,
          localPhotoPath: _photoPath,
          // The live list: a portfolio skill add/remove changes it before
          // the profile is re-fetched.
          skills: _skills.toList(),
        ),
        const SizedBox(height: 16),
        ProfileSection(
          title: 'Personal Information',
          action: ProfileSectionButton(
            label: _editing ? 'Cancel' : 'Edit Profile',
            onPressed: _editing
                ? _cancelEditing
                : () => setState(() => _editing = true),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editing) ...[
                Row(
                  children: [
                    _WorkerProfilePhoto(
                      profile: widget.profile,
                      localPhotoPath: _photoPath,
                      radius: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _photoPath == null ? 'Choose photo' : 'Change photo',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              _ProfileField(
                label: 'First Name',
                controller: _firstName,
                enabled: _editing,
              ),
              _ProfileField(
                label: 'Last Name',
                controller: _lastName,
                enabled: _editing,
              ),
              _ProfileField(
                label: 'Email',
                controller: _email,
                enabled: _editing,
              ),
              _ProfileField(
                label: 'Phone Number',
                controller: _phone,
                enabled: _editing,
              ),
              _ProfileField(
                label: 'Street / House No.',
                controller: _location,
                enabled: _editing,
              ),
              if (_editing) ...[
                const _FieldLabel('Pin your exact location'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 220,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter:
                            _profilePin ?? const LatLng(14.0253, 121.5929),
                        initialZoom: 14,
                        onTap: (_, point) =>
                            setState(() => _profilePin = point),
                      ),
                      children: [
                        if (shouldLoadMapTiles) osmTileLayer(),
                        if (_profilePin != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _profilePin!,
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
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ProfileSection(
          title: 'Services & Rates',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileField(
                label: 'Bio',
                controller: _bio,
                enabled: _editing,
                lines: 3,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ProfileField(
                      label: 'Hourly Rate',
                      controller: _hourly,
                      enabled: _editing,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileField(
                      label: 'Daily Rate',
                      controller: _daily,
                      enabled: _editing,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              _ProfileField(
                label: 'Years of Experience',
                controller: _experience,
                enabled: _editing,
                keyboardType: TextInputType.number,
              ),
              const _FieldLabel('Skill categories used for matching'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ...gawagoSkills
                      .where((skill) => !isOtherSkillChoice(skill))
                      .map(
                        (skill) => FilterChip(
                          label: Text(skill),
                          selected: _skills.contains(skill),
                          onSelected: !_editing
                              ? null
                              : (selected) {
                                  if (selected &&
                                      _skills.length >= maxWorkerSkills) {
                                    _message(
                                      'You can select up to $maxWorkerSkills skills only.',
                                    );
                                    return;
                                  }
                                  setState(
                                    () => selected
                                        ? _skills.add(skill)
                                        : _skills.remove(skill),
                                  );
                                },
                        ),
                      ),
                  // Skills the worker typed (outside the catalog) were
                  // saved but never shown here, so they could not be removed.
                  ..._skills
                      .where((skill) => !gawagoSkills.contains(skill))
                      .map(
                        (skill) => InputChip(
                          label: Text(skill),
                          selected: true,
                          onDeleted: _editing
                              ? () => setState(() => _skills.remove(skill))
                              : null,
                        ),
                      ),
                  if (_editing && _skills.length < maxWorkerSkills)
                    ActionChip(
                      key: const ValueKey('profile-add-typed-skill'),
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Other skill'),
                      onPressed: _addTypedSkillChip,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ProfileSection(
          title: 'Date-Specific Availability',
          action: _editing
              ? ProfileSectionButton(
                  label: '+ Add Date',
                  onPressed: _addDateAvailability,
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_availabilityWindows.isEmpty)
                const SectionEmptyText(
                  'No date-specific availability added yet.',
                )
              else
                ..._availabilityWindows.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value.date),
                    subtitle: Text(
                      '${entry.value.startTime} - ${entry.value.endTime}',
                    ),
                    trailing: _editing
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(
                              () => _availabilityWindows.removeAt(entry.key),
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (_editing) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: GawaGoColors.primary,
                foregroundColor: GawaGoColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: GawaGoColors.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Profile'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FutureBuilder<WorkerPortfolio>(
          future: _portfolio,
          builder: (context, snapshot) {
            final portfolio = snapshot.data ?? WorkerPortfolio.empty;
            final failed = snapshot.hasError;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileSection(
                  title: 'Skills & Expertise',
                  // Offered once the portfolio has loaded: building the
                  // choices from an empty placeholder offered skills the
                  // worker already had.
                  action: _editing && snapshot.hasData
                      ? ProfileSectionButton(
                          label: '+ Add Skill',
                          onPressed: () => _addPortfolioSkill(portfolio.skills),
                        )
                      : null,
                  child: failed
                      ? const SectionEmptyText(
                          'Could not load your portfolio right now.',
                        )
                      : portfolio.skills.isEmpty
                      ? const SectionEmptyText('No skills added yet.')
                      : Column(
                          children: portfolio.skills
                              .map(
                                (skill) => ProfileSkillTile(
                                  skillName: skill.skillName,
                                  proficiencyLabel: skill.proficiencyLabel,
                                  averageRating: skill.averageRating,
                                  ratingCount: skill.ratingCount,
                                  trailing: !_editing
                                      ? null
                                      : IconButton(
                                          tooltip: 'Remove skill',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: () async {
                                            if (_skillChipsUnsaved) {
                                              _message(
                                                'Save your skill changes first, then remove a portfolio skill.',
                                              );
                                              return;
                                            }
                                            if (!await _confirmDelete(
                                              skill.skillName,
                                            )) {
                                              return;
                                            }
                                            await _runPortfolioAction(() async {
                                              await widget.repository
                                                  .deletePortfolioSkill(
                                                    skill.id,
                                                  );
                                              // Removing it here also
                                              // removes it from the profile
                                              // list a later Save sends.
                                              bool sameSkill(String name) =>
                                                  name.toLowerCase() ==
                                                  skill.skillName.toLowerCase();
                                              _skills.removeWhere(sameSkill);
                                              _savedSkills.removeWhere(
                                                sameSkill,
                                              );
                                              widget.onSkillsChanged?.call();
                                            }, 'Skill removed.');
                                          },
                                        ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 16),
                ProfileSection(
                  title: 'Certifications',
                  action: _editing
                      ? ProfileSectionButton(
                          label: '+ Add Certificate',
                          onPressed: _addCertification,
                        )
                      : null,
                  child: failed
                      ? const SectionEmptyText(
                          'Could not load your certificates right now.',
                        )
                      : portfolio.certifications.isEmpty
                      ? const SectionEmptyText('No certifications added yet.')
                      : Column(
                          children: portfolio.certifications
                              .map(
                                (certificate) => _CertificationTile(
                                  certificate: certificate,
                                  editing: _editing,
                                  onDelete: () async {
                                    if (!await _confirmDelete(
                                      certificate.certificateName,
                                    )) {
                                      return;
                                    }
                                    await _runPortfolioAction(
                                      () => widget.repository
                                          .deleteCertification(certificate.id),
                                      'Certificate removed.',
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 16),
                ProfileSection(
                  title: 'Work Samples',
                  action: _editing
                      ? ProfileSectionButton(
                          label: '+ Add Sample',
                          onPressed: _addWorkSample,
                        )
                      : null,
                  child: failed
                      ? const SectionEmptyText(
                          'Could not load your work samples right now.',
                        )
                      : portfolio.workSamples.isEmpty
                      ? const SectionEmptyText('No work samples uploaded yet.')
                      : Column(
                          children: portfolio.workSamples
                              .map(
                                (sample) => _WorkSampleTile(
                                  sample: sample,
                                  editing: _editing,
                                  onEdit: () => _editWorkSample(sample),
                                  onDelete: () async {
                                    if (!await _confirmDelete(
                                      sample.title.isEmpty
                                          ? 'this work sample'
                                          : sample.title,
                                    )) {
                                      return;
                                    }
                                    await _runPortfolioAction(
                                      () => widget.repository.deleteWorkSample(
                                        sample.id,
                                      ),
                                      'Work sample removed.',
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        ProfileSection(
          title: 'Employment History',
          child: FutureBuilder<List<WorkerJob>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SectionEmptyText(
                  'Could not load your job history right now.',
                );
              }
              final jobs = snapshot.data;
              if (jobs == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (jobs.isEmpty) {
                return const SectionEmptyText('No completed jobs yet.');
              }
              return Column(
                children: jobs
                    .map((job) => _EmploymentHistoryTile(job: job))
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A white card with the green title bar the web profile page uses, and an
/// optional action button on the right of that bar.
/// A labelled profile input. Locked fields keep the same shape as editable
/// ones so the page does not jump when editing starts.
class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.lines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int lines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: lines,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 15,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: enabled ? Colors.white : GawaGoColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: GawaGoColors.border),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: GawaGoColors.primary,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificationTile extends StatelessWidget {
  const _CertificationTile({
    required this.certificate,
    required this.editing,
    required this.onDelete,
  });

  final WorkerCertificate certificate;
  final bool editing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The file route needs the bearer token, which Image.network
          // can't send; PDFs get a pointer to the website instead.
          if (certificate.fileUrl.isNotEmpty && certificate.isImage)
            AuthenticatedImage(url: certificate.fileUrl, height: 170)
          else if (certificate.fileUrl.isNotEmpty)
            CertificateFileNote(isPdf: certificate.isPdf),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        certificate.certificateName,
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
                        children: [
                          if (certificate.certificateTypeLabel.isNotEmpty)
                            SoftGreenPill(
                              label: certificate.certificateTypeLabel,
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
                        const SizedBox(height: 6),
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
                if (editing)
                  IconButton(
                    tooltip: 'Remove certificate',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkSampleTile extends StatelessWidget {
  const _WorkSampleTile({
    required this.sample,
    required this.editing,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkSample sample;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sample.title.isEmpty ? 'Untitled sample' : sample.title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _WorkSamplePhoto(
                  url: sample.beforeOrFallback,
                  caption: 'Before',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WorkSamplePhoto(
                  url: sample.afterImageUrl,
                  caption: 'After',
                ),
              ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkSamplePhoto extends StatelessWidget {
  const _WorkSamplePhoto({required this.url, required this.caption});

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

class _EmploymentHistoryTile extends StatelessWidget {
  const _EmploymentHistoryTile({required this.job});

  final WorkerJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.title.isEmpty ? job.jobType : job.title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            job.householdName.isEmpty ? 'Household' : job.householdName,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
          ),
          if (job.locationLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              job.locationLabel,
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (job.jobType.isNotEmpty) SoftGreenPill(label: job.jobType),
              SoftGreenPill(
                label:
                    'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}',
                muted: true,
              ),
            ],
          ),
          JobSkillRatingChips(
            ratings: [
              for (final rating in job.skillRatings)
                MapEntry(rating.skillName, rating.rating),
            ],
          ),
        ],
      ),
    );
  }
}

class _CertificationDraft {
  const _CertificationDraft({
    required this.name,
    required this.type,
    required this.issuer,
    required this.issueDate,
    required this.expiryDate,
    required this.filePath,
  });

  final String name;
  final String type;
  final String issuer;
  final String issueDate;
  final String expiryDate;
  final String? filePath;
}

class _CertificationDialog extends StatefulWidget {
  const _CertificationDialog();

  @override
  State<_CertificationDialog> createState() => _CertificationDialogState();
}

class _CertificationDialogState extends State<_CertificationDialog> {
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  String _type = 'certification';
  DateTime? _issueDate;
  DateTime? _expiryDate;
  String? _filePath;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'Certificate',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _filePath = file.path);
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 40),
      lastDate: DateTime(now.year + 40),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expiry) {
        _expiryDate = picked;
      } else {
        _issueDate = picked;
      }
    });
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the certificate name.');
      return;
    }
    if (_filePath == null) {
      setState(() => _error = 'Attach a photo or PDF of the certificate.');
      return;
    }
    Navigator.pop(
      context,
      _CertificationDraft(
        name: _name.text.trim(),
        type: _type,
        issuer: _issuer.text.trim(),
        issueDate: _issueDate == null ? '' : _dateValue(_issueDate!),
        expiryDate: _expiryDate == null ? '' : _dateValue(_expiryDate!),
        filePath: _filePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add certificate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Certificate name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: WorkerCertificate.typeOptions.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issuer,
              decoration: const InputDecoration(
                labelText: 'Issued by (optional)',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Issue date (optional)'),
              trailing: Text(
                _issueDate == null ? 'Not set' : _dateValue(_issueDate!),
              ),
              onTap: () => _pickDate(expiry: false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Expiry date (optional)'),
              trailing: Text(
                _expiryDate == null ? 'Not set' : _dateValue(_expiryDate!),
              ),
              onTap: () => _pickDate(expiry: true),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _filePath == null
                    ? 'Attach certificate'
                    : _filePath!.split(RegExp(r'[/\\]')).last,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _WorkSampleDraft {
  const _WorkSampleDraft({
    required this.title,
    required this.description,
    required this.beforePath,
    required this.afterPath,
  });

  final String title;
  final String description;
  final String? beforePath;
  final String? afterPath;
}

class _WorkSampleDialog extends StatefulWidget {
  const _WorkSampleDialog({this.existing});

  final WorkSample? existing;

  @override
  State<_WorkSampleDialog> createState() => _WorkSampleDialogState();
}

class _WorkSampleDialogState extends State<_WorkSampleDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  String? _beforePath;
  String? _afterPath;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool after}) async {
    const group = XTypeGroup(
      label: 'Photo',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    setState(() {
      if (after) {
        _afterPath = file.path;
      } else {
        _beforePath = file.path;
      }
    });
  }

  void _submit() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title for this sample.');
      return;
    }
    // On a new sample both photos are the point of the record; on an edit
    // they are optional, because leaving them out keeps the ones already
    // uploaded.
    if (!_isEdit && (_beforePath == null || _afterPath == null)) {
      setState(() => _error = 'Choose both a before and an after photo.');
      return;
    }
    Navigator.pop(
      context,
      _WorkSampleDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        beforePath: _beforePath,
        afterPath: _afterPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit work sample' : 'Add work sample'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _pick(after: false),
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _beforePath == null
                    ? (_isEdit ? 'Replace before photo' : 'Before photo')
                    : _beforePath!.split(RegExp(r'[/\\]')).last,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pick(after: true),
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _afterPath == null
                    ? (_isEdit ? 'Replace after photo' : 'After photo')
                    : _afterPath!.split(RegExp(r'[/\\]')).last,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(_isEdit ? 'Save' : 'Add')),
      ],
    );
  }
}

/// The read-first identity card at the top of My Profile.
class _WorkerProfileSummary extends StatelessWidget {
  const _WorkerProfileSummary({
    required this.profile,
    required this.localPhotoPath,
    required this.skills,
  });

  final WorkerProfile profile;
  final String? localPhotoPath;
  final List<String> skills;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GawaGoColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _WorkerProfilePhoto(
              profile: profile,
              localPhotoPath: localPhotoPath,
              radius: 48,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: GawaGoColors.fontHeading,
              color: GawaGoColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '@${profile.username}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 10),
          const Center(child: SoftGreenPill(label: 'Worker')),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: GawaGoColors.border),
          ),
          _SummaryFact(
            label: 'Barangay',
            value: profile.locationLabel.isEmpty
                ? 'Not set'
                : profile.locationLabel,
          ),
          _SummaryFact(
            label: 'Phone',
            value: profile.phone.isEmpty ? 'Not set' : profile.phone,
          ),
          _SummaryFact(
            label: 'Email',
            value: profile.email.isEmpty ? 'Not set' : profile.email,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: GawaGoColors.border),
          ),
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
              StatusBadge(status: profile.verificationStatus),
            ],
          ),
          const SizedBox(height: 8),
          _SummaryFact(label: 'Rating', value: profile.displayRating),
          _SummaryFact(label: 'Jobs Done', value: '${profile.ratingCount}'),
          _SummaryFact(
            label: 'Hourly Rate',
            value: profile.hourlyRate == null
                ? 'Not disclosed'
                : 'PHP ${profile.hourlyRate!.toStringAsFixed(2)}',
          ),
          _SummaryFact(
            label: 'Daily Rate',
            value: profile.dailyRate == null
                ? 'Not disclosed'
                : 'PHP ${profile.dailyRate!.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills.isEmpty
                ? const [
                    SoftGreenPill(label: 'No skills selected', muted: true),
                  ]
                : skills.map((skill) => SoftGreenPill(label: skill)).toList(),
          ),
        ],
      ),
    );
  }
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({required this.label, required this.value});

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

class _WorkerProfilePhoto extends StatelessWidget {
  const _WorkerProfilePhoto({
    required this.profile,
    required this.localPhotoPath,
    required this.radius,
  });

  final WorkerProfile profile;
  final String? localPhotoPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (localPhotoPath != null && File(localPhotoPath!).existsSync()) {
      image = FileImage(File(localPhotoPath!));
    } else if (profile.profilePhotoUrl.isNotEmpty) {
      image = NetworkImage(profile.profilePhotoUrl);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: GawaGoColors.primary.withValues(alpha: 0.16),
      backgroundImage: image,
      child: image == null
          ? Icon(
              Icons.person_outline,
              size: radius,
              color: GawaGoColors.leafDeep,
            )
          : null,
    );
  }
}

class _WorkerNotifications extends StatefulWidget {
  const _WorkerNotifications({
    super.key,
    required this.repository,
    required this.onOpenJob,
    required this.onToolbarChanged,
    required this.onNotificationsChanged,
  });

  final WorkerRepository repository;
  final ValueChanged<int> onOpenJob;
  final VoidCallback onToolbarChanged;
  final VoidCallback onNotificationsChanged;

  @override
  State<_WorkerNotifications> createState() => _WorkerNotificationsState();
}

class _WorkerNotificationsState extends State<_WorkerNotifications> {
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
      // A network failure here must not block opening the notification --
      // it used to throw and silently stop the whole handler, so the
      // hire-request dialog (below) never opened (F-17).
      try {
        await widget.repository.markNotificationRead(item.id);
      } catch (_) {
        // Still show the notification; it just stays marked unread.
      }
    }
    if (!mounted) return;
    if (item.requiresAction &&
        item.actionType == 'hire_request' &&
        item.applicationId != null) {
      await _showHireRequestDecision(item);
      _reload();
      return;
    }
    final jobId = item.targetJobId;
    if (jobId != null) {
      widget.onOpenJob(jobId);
    } else {
      await _showDetails(item);
    }
    _reload();
  }

  Future<void> _showHireRequestDecision(WorkerNotification item) async {
    WorkerJob? job;
    final jobId = item.targetJobId;
    if (jobId != null) {
      try {
        job = await widget.repository.getJob(jobId);
      } catch (_) {
        job = null;
      }
    }
    if (!mounted) return;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: const BoxDecoration(
                  color: GawaGoColors.cardGreen,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HIRE REQUEST',
                      style: TextStyle(
                        color: GawaGoColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      job?.title ?? item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        color: GawaGoColors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.message.isEmpty
                          ? 'A household wants to hire you for this job.'
                          : item.message,
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        height: 1.3,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: job == null
                      ? const Text(
                          'Job details are not available yet. You can still respond from this request.',
                          style: TextStyle(color: GawaGoColors.textMuted),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: _HireRequestFact(
                                    label: 'Household',
                                    value: job.householdName.isEmpty
                                        ? job.householdUsername
                                        : job.householdName,
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child: _HireRequestFact(
                                    label: 'Rate',
                                    value:
                                        'PHP ${job.serviceRate.toStringAsFixed(2)} / ${job.rateTypeLabel}',
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child: _HireRequestFact(
                                    label: 'Schedule',
                                    value: _scheduleLabel(job.schedule),
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child: _HireRequestFact(
                                    label: 'Distance',
                                    value: _distanceLabel(job.distanceKm),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _HireRequestFact(
                              label: 'Job background',
                              value: job.description.isEmpty
                                  ? 'No description provided.'
                                  : job.description,
                              multiline: true,
                            ),
                            _HireRequestFact(
                              label: 'Location',
                              value: job.locationLabel.isEmpty
                                  ? 'Not set'
                                  : job.locationLabel,
                              multiline: true,
                            ),
                            if (job.images.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'Reference images',
                                style: TextStyle(
                                  color: GawaGoColors.ink,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              JobImageGallery(images: job.images),
                            ],
                            const SizedBox(height: 16),
                            const Text(
                              'Household reviews',
                              style: TextStyle(
                                fontFamily: GawaGoColors.fontHeading,
                                color: GawaGoColors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<GawaGoReview>>(
                              future: widget.repository.getHouseholdReviews(
                                job.householdUsername,
                              ),
                              builder: (context, reviews) {
                                final items =
                                    reviews.data ?? const <GawaGoReview>[];
                                if (reviews.connectionState ==
                                        ConnectionState.waiting &&
                                    !reviews.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                if (items.isEmpty) {
                                  return const _HireRequestReviewBox(
                                    text:
                                        'No worker feedback for this household yet.',
                                  );
                                }
                                return Column(
                                  children: items.take(3).map((review) {
                                    final rating = review.rating == null
                                        ? 'Feedback'
                                        : '${review.rating!.toStringAsFixed(1)} / 5';
                                    return _HireRequestReviewBox(
                                      text:
                                          '$rating - ${review.feedback.isEmpty ? 'No written feedback.' : review.feedback}',
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (jobId != null)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, 'details'),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open full job details'),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, 'reject'),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, 'accept'),
                            child: const Text('Accept'),
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
    if (decision == null || item.applicationId == null) return;
    if (decision == 'details') {
      if (jobId != null) widget.onOpenJob(jobId);
      return;
    }
    try {
      await widget.repository.decideHireRequest(item.applicationId!, decision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'accept'
                  ? 'Hire request accepted.'
                  : 'Hire request rejected.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  Future<void> _showDetails(WorkerNotification item) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.message),
            const SizedBox(height: 12),
            if (item.actorUsername.isNotEmpty)
              Text('From: @${item.actorUsername}'),
            if (item.applicationId != null)
              Text('Application: #${item.applicationId}'),
            Text(item.displayDate),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
                  onSelected: (action) async {
                    if (action == 'details') {
                      await _viewDetails(item);
                    } else if (action == 'read') {
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

class _WorkerVerification extends StatefulWidget {
  const _WorkerVerification({
    required this.repository,
    required this.onSubmitted,
  });

  final WorkerRepository repository;
  final VoidCallback onSubmitted;

  @override
  State<_WorkerVerification> createState() => _WorkerVerificationState();
}

class _WorkerVerificationState extends State<_WorkerVerification> {
  late Future<List<VerificationRequest>> _future = widget.repository
      .getVerificationRequests();
  String? _primary;
  String? _secondary;
  String? _idType;
  final _idOtherName = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;

  Future<String?> _pick() async {
    const group = XTypeGroup(
      label: 'Verification documents',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    return file?.path;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_primary == null || _secondary == null) {
      _message('Choose both required verification documents.');
      return;
    }
    if (_idType == null) {
      _message('Choose which government ID you are uploading.');
      return;
    }
    if (_idType == 'other' && _idOtherName.text.trim().isEmpty) {
      _message('Name the government ID you are uploading.');
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
      if (mounted) _message('Verification submitted for admin review.');
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VerificationRequest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () {
              setState(() {
                _future = widget.repository.getVerificationRequests();
              });
            },
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
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(
                        status: latest.status,
                        prefix: 'Status',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Submitted: ${formatLocalDateTime(latest.submittedAt)}',
                    ),
                    Text('Primary ID: ${latest.primaryName}'),
                    Text('Supporting document: ${latest.secondaryName}'),
                    if (latest.reviewNote.isNotEmpty)
                      Text('Admin note: ${latest.reviewNote}'),
                  ],
                ),
              ),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: StatusCard(
                  icon: verified
                      ? Icons.verified_outlined
                      : Icons.pending_actions_outlined,
                  title: verified
                      ? 'You are already verified'
                      : 'Verification is under review',
                  subtitle: verified
                      ? 'Your worker account has been approved. Your verification details are now read-only.'
                      : 'Your submission is locked while the admin reviews your documents.',
                  status: latest.status,
                ),
              )
            else ...[
              const _WorkerVerificationIntro(),
              const SizedBox(height: 12),
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
              _WorkerVerificationPicker(
                title: 'Primary ID document',
                subtitle: 'A clear photo or scan of the ID you chose above.',
                path: _primary,
                icon: Icons.badge_outlined,
                onPick: () async {
                  final path = await _pick();
                  if (path != null) setState(() => _primary = path);
                },
              ),
              const SizedBox(height: 12),
              _WorkerVerificationPicker(
                title: 'Supporting document',
                subtitle: 'Proof of work, address, or another supporting file.',
                path: _secondary,
                icon: Icons.description_outlined,
                onPick: () async {
                  final path = await _pick();
                  if (path != null) setState(() => _secondary = path);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
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

class _WorkerVerificationIntro extends StatelessWidget {
  const _WorkerVerificationIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GawaGoColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.primary.withValues(alpha: 0.45)),
      ),
      child: const Text(
        'Submit clear documents to receive a verification badge and higher priority in smart matching.',
        style: TextStyle(color: GawaGoColors.ink, height: 1.4),
      ),
    );
  }
}

class _WorkerVerificationPicker extends StatelessWidget {
  const _WorkerVerificationPicker({
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

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _HireRequestFact extends StatelessWidget {
  const _HireRequestFact({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
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
              color: GawaGoColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? 'Not available' : value,
            maxLines: multiline ? null : 2,
            overflow: multiline ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              color: GawaGoColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HireRequestReviewBox extends StatelessWidget {
  const _HireRequestReviewBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: GawaGoColors.textMuted,
          height: 1.3,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

String _scheduleLabel(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value.trim().isEmpty ? 'Schedule not set' : value;
  final local = parsed.toLocal();
  return '${_month(local.month)} ${local.day}, ${local.year} at ${_clockLabel(local)}';
}

String _jobDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value.trim().isEmpty ? 'Not Set' : value;
  final local = parsed.toLocal();
  return '${_month(local.month)} ${local.day}, ${local.year}';
}

String _distanceLabel(double? value) => value == null
    ? 'Distance unavailable'
    : '${value.toStringAsFixed(1)} km away';

String _clockLabel(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _month(int value) => const [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value.clamp(1, 12)];

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'H';
  return trimmed.characters.first.toUpperCase();
}

String _title(_WorkerPage page) => switch (page) {
  _WorkerPage.dashboard => 'Dashboard',
  _WorkerPage.jobs => 'Find Jobs',
  _WorkerPage.applications => 'My Applications',
  _WorkerPage.myJobs => 'My Jobs',
  _WorkerPage.messages => 'Messages',
  _WorkerPage.myReports => 'My Reports',
  _WorkerPage.profile => 'My Profile',
  _WorkerPage.reviews => 'Reviews & Feedback',
  _WorkerPage.notifications => 'Notifications',
  _WorkerPage.verification => 'Get Verified',
};

IconData _icon(_WorkerPage page) => switch (page) {
  _WorkerPage.dashboard => Icons.dashboard_outlined,
  _WorkerPage.jobs => Icons.search,
  _WorkerPage.applications => Icons.description_outlined,
  _WorkerPage.myJobs => Icons.work_outline,
  _WorkerPage.messages => Icons.chat_bubble_outline,
  _WorkerPage.myReports => Icons.flag_outlined,
  _WorkerPage.profile => Icons.person_outline,
  _WorkerPage.reviews => Icons.star_outline,
  _WorkerPage.notifications => Icons.notifications_none,
  _WorkerPage.verification => Icons.verified_outlined,
};

String _timeValue(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';

String _dateValue(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

double _coordinateForApi(double value) =>
    double.parse(value.toStringAsFixed(7));
