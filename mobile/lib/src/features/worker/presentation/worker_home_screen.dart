import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/constants/gawago_options.dart';
import '../../../shared/utils/display_formatters.dart';
import '../../../shared/utils/map_tile_guard.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../../../shared/widgets/form_section.dart';
import '../../../shared/widgets/job_image_gallery.dart';
import '../../../shared/widgets/location_route_map.dart';
import '../../../shared/widgets/notification_badge.dart';
import '../../../shared/widgets/review_history.dart';
import '../../../shared/widgets/status_card.dart';
import '../data/worker_models.dart';
import '../data/worker_repository.dart';

enum _WorkerPage {
  dashboard,
  jobs,
  applications,
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

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  static const _primaryPages = [
    _WorkerPage.dashboard,
    _WorkerPage.jobs,
    _WorkerPage.applications,
    _WorkerPage.notifications,
  ];

  static const _accountPages = [_WorkerPage.profile, _WorkerPage.verification];

  WorkerRepository get _repository => widget.repository;
  final _notificationKey = GlobalKey<_WorkerNotificationsState>();
  _WorkerPage _page = _WorkerPage.dashboard;
  final Set<_WorkerPage> _visitedPages = {_WorkerPage.dashboard};
  late Future<int> _unreadCount;
  int _refreshKey = 0;
  String? _initialJobSkill;

  @override
  void initState() {
    super.initState();
    _unreadCount = _loadUnreadCount();
  }

  Future<int> _loadUnreadCount() async {
    final notifications = await _repository.getNotifications();
    return notifications.where((item) => !item.isRead).length;
  }

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
      _refreshKey++;
    });
  }

  Future<void> _logout() async {
    await SessionStorage.clear();
    widget.onLogout();
  }

  void _refreshAll() {
    setState(() {
      _refreshKey++;
      _unreadCount = _loadUnreadCount();
    });
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
                label: _title(page),
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
                      key: ValueKey('${page.name}-$_refreshKey'),
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
        initialSkill: _initialJobSkill,
      ),
      _WorkerPage.applications => _WorkerApplications(repository: _repository),
      _WorkerPage.profile => _WorkerProfile(
        repository: _repository,
        onSaved: _refreshAll,
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
          onChanged: _refreshAll,
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
      constraints: const BoxConstraints(minHeight: 86),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Welcome, ${profile.fullName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
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

class _WebsiteMetricGrid extends StatelessWidget {
  const _WebsiteMetricGrid({required this.metrics});

  final List<_WebsiteMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 320 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 116,
          ),
          itemBuilder: (context, index) => _MetricTile(metrics[index]),
        );
      },
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
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: highlighted ? GawaGoColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: highlighted
            ? null
            : Border.all(color: const Color(0xFFD8D0C3), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label.toUpperCase(),
            style: TextStyle(
              color: highlighted ? Colors.white : const Color(0xFF5D6B61),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          if (hasStatus)
            _LargeStatusBadge(status: metric.statusValue!)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                metric.value,
                style: TextStyle(
                  color: highlighted ? Colors.white : GawaGoColors.ink,
                  fontSize: highlighted ? 42 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
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
        color: const Color(0xFFE7F5E9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF9BD9A9), width: 1.5),
      ),
      child: Text(
        formatStatus(status),
        style: const TextStyle(
          color: Color(0xFF197A35),
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
        .where((skill) => query.isEmpty || skill.toLowerCase().contains(query))
        .toList();
    final workerSkills = widget.profile.skills.map(_normalizeSkill).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth >= 360;
              final searchField = SizedBox(
                width: useRow ? 184 : double.infinity,
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  style: const TextStyle(fontSize: 14, letterSpacing: 0),
                  decoration: InputDecoration(
                    hintText: 'Search category...',
                    hintStyle: const TextStyle(color: Color(0xFF6C6C6C)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: GawaGoColors.ink,
                        width: 1.2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: GawaGoColors.ink,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              );

              final title = const Text(
                'Job Market Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: GawaGoColors.ink,
                  letterSpacing: 0,
                ),
              );

              if (!useRow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 10), searchField],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 10),
                  searchField,
                ],
              );
            },
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 320 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleSkills.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                mainAxisExtent: 148,
              ),
              itemBuilder: (context, index) {
                final skill = visibleSkills[index];
                final count = widget.jobs
                    .where(
                      (job) =>
                          _normalizeSkill(job.jobType) ==
                              _normalizeSkill(skill) ||
                          _normalizeSkill(job.requiredSkill) ==
                              _normalizeSkill(skill),
                    )
                    .length;
                final matches = workerSkills.contains(_normalizeSkill(skill));
                return _MarketCategoryCard(
                  skill: skill,
                  openCount: count,
                  matches: matches,
                  onTap: () => widget.onOpenJobs(skill),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _MarketCategoryCard extends StatelessWidget {
  const _MarketCategoryCard({
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
    final borderColor = matches
        ? GawaGoColors.primary
        : const Color(0xFFD8D0C3);
    final surfaceColor = matches
        ? const Color(0xFFF4FBF6)
        : const Color(0xFFF9F9F9);
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 148),
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                skill,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$openCount open ${openCount == 1 ? 'job' : 'jobs'}',
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF4D4D4D),
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.center,
                child: _SkillMatchPill(matches: matches),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerJobs extends StatefulWidget {
  const _WorkerJobs({
    required this.repository,
    required this.onChanged,
    this.initialSkill,
  });

  final WorkerRepository repository;
  final VoidCallback onChanged;
  final String? initialSkill;

  @override
  State<_WorkerJobs> createState() => _WorkerJobsState();
}

class _WorkerJobsState extends State<_WorkerJobs> {
  late String? _skill = widget.initialSkill;
  final _location = TextEditingController();
  late Future<(List<WorkerJob>, WorkerProfile)> _future = _load();

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

  Future<void> _openJob(WorkerJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkerJobDetail(
          repository: widget.repository,
          jobId: job.id,
          onChanged: widget.onChanged,
        ),
      ),
    );
    _filter();
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<(List<WorkerJob>, WorkerProfile)>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(
                  error: snapshot.error,
                  onRetry: () => setState(() {}),
                );
              }
              if (!snapshot.hasData) return const AppLoadingState();
              final jobs = snapshot.data!.$1;
              final workerSkills = snapshot.data!.$2.skills
                  .map(_normalizeSkill)
                  .toSet();
              final sortedJobs = [...jobs]
                ..sort((first, second) {
                  final firstMatches = _jobMatchesWorkerSkills(
                    first,
                    workerSkills,
                  );
                  final secondMatches = _jobMatchesWorkerSkills(
                    second,
                    workerSkills,
                  );
                  if (firstMatches == secondMatches) return 0;
                  return firstMatches ? -1 : 1;
                });
              if (jobs.isEmpty) {
                return const AppEmptyState(
                  message: 'No matching jobs available.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _filter(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                  children: [
                    const Text(
                      'Available Jobs',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _WorkerJobsFilterCard(
                      skill: _skill,
                      location: _location,
                      onSkillChanged: (value) => _skill = value,
                      onFilter: _filter,
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Jobs matching your skills appear first',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...sortedJobs.map(
                      (job) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _AvailableJobCard(
                          job: job,
                          matchesSkills: _jobMatchesWorkerSkills(
                            job,
                            workerSkills,
                          ),
                          onViewDetails: () => _openJob(job),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border, width: 1.1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Job type',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: skill,
                      decoration: const InputDecoration(
                        hintText: 'All Types',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Types'),
                        ),
                        ...gawagoSkills.map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        ),
                      ],
                      onChanged: onSkillChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Barangay',
                      style: TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: location,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Poblacion',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.tonal(
              onPressed: onFilter,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFFB9B9B9)),
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

class _AvailableJobCard extends StatelessWidget {
  const _AvailableJobCard({
    required this.job,
    required this.matchesSkills,
    required this.onViewDetails,
  });

  final WorkerJob job;
  final bool matchesSkills;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final title = job.jobType.isNotEmpty ? job.jobType : job.title;
    final borderColor = matchesSkills
        ? GawaGoColors.primary
        : const Color(0xFFD8D0C3);
    return Material(
      color: const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onViewDetails,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 7,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SkillMatchPill(matches: matchesSkills),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                job.description.trim().isEmpty
                    ? 'Descriptions...'
                    : _shortText(job.description.trim(), 80),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF454545),
                  fontSize: 14,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                job.locationLabel.isEmpty
                    ? 'Location not set'
                    : job.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 14,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _scheduleLabel(job.schedule),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF454545),
                  fontSize: 14,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'PHP ${job.serviceRate.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const TextSpan(text: ' / Per Day'),
                  ],
                ),
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 15,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                job.householdName.isEmpty ? 'Household' : job.householdName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF454545),
                  fontSize: 14,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              if (job.distanceKm != null)
                _SoftPill(
                  label: '${job.distanceKm!.toStringAsFixed(1)} km away',
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: onViewDetails,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.ink,
                    side: const BorderSide(color: Color(0xFFB9B9B9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  child: const Text('View Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  const _SoftPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: GawaGoColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SkillMatchPill extends StatelessWidget {
  const _SkillMatchPill({required this.matches});

  final bool matches;

  @override
  Widget build(BuildContext context) {
    final color = matches ? GawaGoColors.primary : const Color(0xFF6C7870);
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
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      setState(() {
        _future = _load();
      });
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
    controller.dispose();
    return result;
  }

  Future<void> _review(WorkerJob job) async {
    double rating = 5;
    final feedback = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Leave Feedback for Household'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<double>(
                initialValue: rating,
                items: [1, 2, 3, 4, 5]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value.toDouble(),
                        child: Text('$value star${value == 1 ? '' : 's'}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => rating = value ?? 5),
              ),
              TextField(
                controller: feedback,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Feedback'),
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
                label: const Text('Apply'),
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
                label: const Text('Accept Hire Request'),
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
                label: const Text('Reject'),
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
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            children: [
              const Text(
                'Jobs Details',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'DISTANCE & LOCATIONS',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 284,
                  decoration: BoxDecoration(
                    border: Border.all(color: GawaGoColors.ink, width: 1.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: LocationRouteMap(
                    start: workerPoint,
                    end: jobPoint,
                    startLabel: 'Worker',
                    endLabel: 'Job',
                    routePoints: job.routePoints
                        .map((point) => LatLng(point.latitude, point.longitude))
                        .toList(),
                    roadDistanceKm: job.distanceKm,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _WorkerDistanceStrip(job: job),
              const SizedBox(height: 16),
              _WorkerHouseholdProfileCard(job: job),
              const SizedBox(height: 16),
              _WorkerJobDetailsCard(
                job: job,
                busy: _busy,
                actions: actions,
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 24),
              _WorkerPhotosCard(images: job.images),
              if (job.application != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    status: job.application!.status,
                    prefix: 'Application',
                    label: applicationStatusLabel(job.application!.status),
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

class _WorkerDistanceStrip extends StatelessWidget {
  const _WorkerDistanceStrip({required this.job});

  final WorkerJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3E3E3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB9B9B9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.distanceKm == null
                      ? 'Distance unavailable'
                      : '${job.distanceKm!.toStringAsFixed(1)} km away',
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'From your location',
                  style: TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              job.locationLabel.isEmpty
                  ? 'Location not set'
                  : job.locationLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF868686),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerHouseholdProfileCard extends StatelessWidget {
  const _WorkerHouseholdProfileCard({required this.job});

  final WorkerJob job;

  @override
  Widget build(BuildContext context) {
    final name = job.householdName.isNotEmpty
        ? job.householdName
        : job.householdUsername;
    return _WorkerOutlinedPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WorkerPanelHeader('Household Profile'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFE1E1E1),
                  child: Text(
                    _initial(name),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Household' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: GawaGoColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        job.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8A8A8A),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (job.householdUsername.isNotEmpty)
                        Text(
                          '@${job.householdUsername}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                    ],
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
  });

  final WorkerJob job;
  final bool busy;
  final List<Widget> actions;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = job.jobType.isNotEmpty ? job.jobType : job.title;
    return _WorkerOutlinedPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WorkerPanelHeader(
            title.toUpperCase(),
            trailing: const _WorkerOpenPill(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WorkerDetailRow(label: 'Service', value: job.requiredSkill),
                _WorkerDetailRow(
                  label: 'Schedule',
                  value: _scheduleLabel(job.schedule),
                ),
                _WorkerDetailRow(label: 'Date', value: _jobDate(job.schedule)),
                _WorkerDetailRow(label: 'Time', value: _jobTime(job.schedule)),
                const _WorkerDetailRow(label: 'Needed', value: 'See posting'),
                _WorkerDetailRow(
                  label: 'Rate',
                  value: 'PHP ${job.serviceRate.toStringAsFixed(2)} / Per day',
                ),
                _WorkerDetailRow(
                  label: 'Location',
                  value: job.locationLabel.isEmpty
                      ? 'Location not set'
                      : job.locationLabel,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Descriptions',
                  style: TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  job.description.trim().isEmpty
                      ? 'No description.'
                      : job.description.trim(),
                  style: const TextStyle(
                    color: GawaGoColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : onBack,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GawaGoColors.ink,
                        side: const BorderSide(color: Color(0xFFB9B9B9)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text('Back to Find Jobs'),
                    ),
                    ...actions.map(
                      (action) => SizedBox(width: 188, child: action),
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

class _WorkerPhotosCard extends StatelessWidget {
  const _WorkerPhotosCard({required this.images});

  final List<JobImage> images;

  @override
  Widget build(BuildContext context) {
    return _WorkerOutlinedPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WorkerPanelHeader('Photos of Work Area'),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              children: [
                const Text(
                  'These photos help workers see the area before applying.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 20),
                if (images.isEmpty)
                  const _WorkerPhotoPlaceholder(label: 'NO IMAGE')
                else
                  JobImageGallery(images: images),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerPhotoPlaceholder extends StatelessWidget {
  const _WorkerPhotoPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.bottomLeft,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

class _WorkerOutlinedPanel extends StatelessWidget {
  const _WorkerOutlinedPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.ink, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WorkerPanelHeader extends StatelessWidget {
  const _WorkerPanelHeader(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFD9D9D9),
        border: Border(bottom: BorderSide(color: GawaGoColors.ink, width: 1.1)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _WorkerOpenPill extends StatelessWidget {
  const _WorkerOpenPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Text(
        'OPEN',
        style: TextStyle(
          color: GawaGoColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _WorkerDetailRow extends StatelessWidget {
  const _WorkerDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFD0D0D0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8A8A8A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not Set' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
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
        if (snapshot.data!.isEmpty) {
          return const AppEmptyState(message: 'You have no job applications.');
        }
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
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
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
                        value: 'Waiting for Household Confirmation',
                        child: Text('Waiting for Household'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'Completed',
                        child: Text('Completed'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _reload,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Filter'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const AppEmptyState(
                message: 'No applications found for this status.',
              )
            else
              ...visible.map(
                (item) => StatusCard(
                  icon: Icons.assignment_outlined,
                  title: item.jobTitle.isEmpty ? item.jobType : item.jobTitle,
                  status: _workerApplicationDisplayStatus(item),
                  subtitle: _workerApplicationSummary(item),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _workerApplicationDisplayStatus(WorkerApplication item) {
  final jobStatus = item.jobStatus.trim().toLowerCase();
  if (jobStatus == 'completion_requested') {
    return 'Waiting for Household Confirmation';
  }
  if (jobStatus == 'completed') return 'Hired';
  return applicationStatusLabel(item.status.isEmpty ? 'pending' : item.status);
}

String _workerApplicationSummary(WorkerApplication item) {
  final household = item.householdName.isNotEmpty
      ? item.householdName
      : item.householdUsername.isNotEmpty
      ? '@${item.householdUsername}'
      : 'Household';
  final distance = item.distanceKm == null
      ? item.locationLabel
      : '${item.distanceKm!.toStringAsFixed(1)} km away';
  final rate = 'PHP ${item.serviceRate.toStringAsFixed(2)} / Per Day';
  final schedule = _workerApplicationSchedule(item);
  return [
    'Service: ${item.jobType.isEmpty ? 'Not set' : item.jobType}',
    household,
    'Schedule: $schedule',
    if (distance.trim().isNotEmpty) distance,
    if (item.locationLabel.trim().isNotEmpty) 'Location: ${item.locationLabel}',
    rate,
    'Applied: ${formatLocalDateTime(item.appliedAt)}',
    if (item.jobDescription.trim().isNotEmpty)
      'Description: ${_shortText(item.jobDescription.trim(), 120)}',
    if (item.note.isNotEmpty) 'Note: ${item.note}',
  ].join('\n');
}

String _workerApplicationSchedule(WorkerApplication item) {
  if (item.jobPreferredDate.isNotEmpty && item.jobPreferredTime.isNotEmpty) {
    return '${_jobDate(item.jobPreferredDate)} at ${_timeLabel(item.jobPreferredTime)}';
  }
  if (item.jobPreferredDate.isNotEmpty) return _jobDate(item.jobPreferredDate);
  return _scheduleLabel(item.jobSchedule);
}

class _WorkerProfile extends StatefulWidget {
  const _WorkerProfile({required this.repository, required this.onSaved});

  final WorkerRepository repository;
  final VoidCallback onSaved;

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
  });

  final WorkerProfile profile;
  final WorkerRepository repository;
  final VoidCallback onSaved;

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
  late final List<WeeklyAvailability> _availability = [
    ...widget.profile.weeklyAvailability,
  ];
  late final List<AvailabilityWindow> _availabilityWindows = [
    ...widget.profile.availabilityWindows,
  ];
  String? _photoPath;
  bool _saving = false;

  Future<void> _pickPhoto() async {
    const group = XTypeGroup(
      label: 'Profile photo',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _photoPath = file.path);
  }

  Future<void> _save() async {
    if (_profilePin == null) {
      _message('Select your exact Tayabas location on the map.');
      return;
    }
    if ((double.tryParse(_hourly.text) ?? 0) <= 0 &&
        (double.tryParse(_daily.text) ?? 0) <= 0) {
      _message('Enter an hourly or daily service rate.');
      return;
    }
    if (_availability.any((item) => item.startTime == item.endTime) ||
        _availabilityWindows.any((item) => item.startTime == item.endTime)) {
      _message('Availability start and end time must be different.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'bio': _bio.text.trim(),
        'hourly_rate': _hourly.text.trim(),
        'daily_rate': _daily.text.trim(),
        'years_experience': int.tryParse(_experience.text) ?? 0,
        'location_label': _location.text.trim(),
        'latitude': _coordinateForApi(_profilePin!.latitude),
        'longitude': _coordinateForApi(_profilePin!.longitude),
        'skills': _skills.toList(),
      }, profilePhotoPath: _photoPath);
      await widget.repository.saveAvailabilityWindows(_availabilityWindows);
      await widget.repository.saveWeeklyAvailability(_availability);
      if (mounted) _message('Profile and availability saved.');
      widget.onSaved();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAvailability() async {
    int weekday = 0;
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add availability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: weekday,
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(_weekday(index)),
                  ),
                ),
                onChanged: (value) =>
                    setDialogState(() => weekday = value ?? 0),
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
        _availability.add(
          WeeklyAvailability(
            weekday: weekday,
            label: _weekday(weekday),
            startTime: _timeValue(start),
            endTime: _timeValue(end),
          ),
        );
      });
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

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final rates = [
      if (widget.profile.hourlyRate != null)
        'Hourly: PHP ${widget.profile.hourlyRate!.toStringAsFixed(2)}',
      if (widget.profile.dailyRate != null)
        'Daily: PHP ${widget.profile.dailyRate!.toStringAsFixed(2)}',
    ].join('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _WorkerProfileSummary(
          profile: widget.profile,
          localPhotoPath: _photoPath,
          rates: rates,
        ),
        const SizedBox(height: 12),
        Text(
          'Edit Profile Information',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        FormSection(
          number: 1,
          title: 'Profile photo',
          subtitle: 'Use a clear photo so households can recognize you.',
          child: Row(
            children: [
              _WorkerProfilePhoto(
                profile: widget.profile,
                localPhotoPath: _photoPath,
                radius: 34,
              ),
              const SizedBox(width: 16),
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
        ),
        FormSection(
          number: 2,
          title: 'Account details',
          subtitle: 'Keep your identity and contact information accurate.',
          child: Column(
            children: [
              _field(_firstName, 'First name'),
              _field(_lastName, 'Last name'),
              _field(_email, 'Email'),
              _field(_phone, 'Phone'),
            ],
          ),
        ),
        FormSection(
          number: 3,
          title: 'Registered location',
          subtitle: 'Households use this point for distance matching.',
          child: Column(
            children: [
              _field(_location, 'Location'),
              SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter:
                        _profilePin ?? const LatLng(14.0253, 121.5929),
                    initialZoom: 14,
                    onTap: (_, point) => setState(() => _profilePin = point),
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
            ],
          ),
        ),
        FormSection(
          number: 4,
          title: 'Services and rates',
          subtitle: 'Describe your work and disclose at least one rate.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_bio, 'Bio', lines: 3),
              Row(
                children: [
                  Expanded(child: _field(_hourly, 'Hourly rate')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_daily, 'Daily rate')),
                ],
              ),
              _field(_experience, 'Years of experience'),
              const Text(
                'Skills',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 6,
                children: gawagoSkills
                    .map(
                      (skill) => FilterChip(
                        label: Text(skill),
                        selected: _skills.contains(skill),
                        onSelected: (selected) {
                          if (selected && _skills.length >= 4) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You can select up to 4 skills only.',
                                ),
                              ),
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
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        FormSection(
          number: 5,
          title: 'Date-specific availability',
          subtitle: 'Optional schedule entries for particular dates.',
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _addDateAvailability,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Date'),
                ),
              ),
              ..._availabilityWindows.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.date),
                  subtitle: Text(
                    '${entry.value.startTime} - ${entry.value.endTime}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(
                      () => _availabilityWindows.removeAt(entry.key),
                    ),
                  ),
                ),
              ),
              if (_availabilityWindows.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No date-specific availability added yet.'),
                ),
            ],
          ),
        ),
        FormSection(
          number: 6,
          title: 'Weekly availability',
          subtitle: 'Save your normal weekly schedule for household reference.',
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _addAvailability,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Schedule'),
                ),
              ),
              ..._availability.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.label),
                  subtitle: Text(
                    '${entry.value.startTime} - ${entry.value.endTime}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _availability.removeAt(entry.key)),
                  ),
                ),
              ),
              if (_availability.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No availability schedule added yet.'),
                ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Profile'),
          ),
        ),
      ],
    );
  }
}

class _WorkerProfileSummary extends StatelessWidget {
  const _WorkerProfileSummary({
    required this.profile,
    required this.localPhotoPath,
    required this.rates,
  });

  final WorkerProfile profile;
  final String? localPhotoPath;
  final String rates;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorkerProfilePhoto(
              profile: profile,
              localPhotoPath: localPhotoPath,
              radius: 30,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.fullName,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusBadge(status: profile.verificationStatus),
                  const SizedBox(height: 8),
                  Text(
                    '@${profile.username}\n'
                    'Rating: ${profile.displayRating}\n'
                    'Experience: ${profile.yearsExperience} year(s)\n'
                    '${rates.isEmpty ? 'Rates not disclosed yet' : rates}\n'
                    'Skills: ${profile.skills.isEmpty ? 'No skills selected' : profile.skills.join(', ')}',
                    style: const TextStyle(color: GawaGoColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
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
              color: GawaGoColors.primary,
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
      await widget.repository.markNotificationRead(item.id);
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
                        color: GawaGoColors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
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
                        color: Color(0xFF4A5E4F),
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
                                        'PHP ${job.serviceRate.toStringAsFixed(2)} / Per Day',
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
                                color: GawaGoColors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
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
    await widget.repository.deleteNotification(item.id);
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
                      await widget.repository.markNotificationRead(item.id);
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
    if (_primary == null || _secondary == null) {
      _message('Choose both required verification documents.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.submitVerification(
        primaryPath: _primary!,
        secondaryPath: _secondary!,
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
              _WorkerVerificationPicker(
                title: 'Primary ID document',
                subtitle: 'Government-issued ID or a clear identity document.',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: GawaGoColors.primary),
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
        color: const Color(0xFFF8F5EE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GawaGoColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4A5E4F),
          height: 1.3,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

Widget _field(TextEditingController controller, String label, {int lines = 1}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

String _shortText(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength).trimRight()}...';
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

String _jobTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value.trim().isEmpty ? 'Not Set' : value;
  return _clockLabel(parsed.toLocal());
}

String _timeLabel(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value.trim().isEmpty ? 'Not Set' : value;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return value.trim().isEmpty ? 'Not Set' : value;
  }
  return _clockLabel(DateTime(2000, 1, 1, hour, minute));
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
  _WorkerPage.profile => 'My Profile',
  _WorkerPage.reviews => 'Reviews & Feedback',
  _WorkerPage.notifications => 'Notifications',
  _WorkerPage.verification => 'Get Verified',
};

IconData _icon(_WorkerPage page) => switch (page) {
  _WorkerPage.dashboard => Icons.dashboard_outlined,
  _WorkerPage.jobs => Icons.search,
  _WorkerPage.applications => Icons.description_outlined,
  _WorkerPage.profile => Icons.person_outline,
  _WorkerPage.reviews => Icons.star_outline,
  _WorkerPage.notifications => Icons.notifications_none,
  _WorkerPage.verification => Icons.verified_outlined,
};

String _weekday(int value) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][value];

String _timeValue(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';

String _dateValue(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

double _coordinateForApi(double value) =>
    double.parse(value.toStringAsFixed(7));
