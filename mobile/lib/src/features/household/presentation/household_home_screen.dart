import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/gawago_colors.dart';
import '../../../shared/constants/gawago_options.dart';
import '../../../shared/utils/display_formatters.dart';
import '../../../shared/utils/map_tile_guard.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../../../shared/widgets/job_image_gallery.dart';
import '../../../shared/widgets/location_route_map.dart';
import '../../../shared/widgets/notification_badge.dart';
import '../../../shared/widgets/persistent_action_bar.dart';
import '../../../shared/widgets/review_history.dart';
import '../../../shared/widgets/status_card.dart';
import '../../worker/data/worker_models.dart';
import '../data/household_models.dart';
import '../data/household_repository.dart';

enum _Page {
  dashboard,
  postJob,
  jobs,
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

class _HouseholdHomeScreenState extends State<HouseholdHomeScreen> {
  static const _primaryPages = [
    _Page.dashboard,
    _Page.postJob,
    _Page.jobs,
    _Page.notifications,
  ];

  static const _accountPages = [_Page.profile, _Page.verification];

  HouseholdRepository get _repository => widget.repository;
  final _notificationKey = GlobalKey<_NotificationsState>();
  _Page _page = _Page.dashboard;
  final Set<_Page> _visitedPages = {_Page.dashboard};
  late Future<int> _unreadCount;
  int _refresh = 0;

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

  Future<void> _logout() async {
    await SessionStorage.clear();
    widget.onLogout();
  }

  void _select(_Page page) {
    setState(() {
      _page = page;
      _visitedPages.add(page);
    });
  }

  void _changed() {
    setState(() {
      _refresh++;
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
                      key: ValueKey('${page.name}-$_refresh'),
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
        onOpenServiceReview: _openServiceReview,
      ),
      _Page.postJob => _PostJob(
        repository: _repository,
        onCancel: () => _select(_Page.dashboard),
        onCreated: () {
          _changed();
          setState(() {
            _page = _Page.jobs;
            _visitedPages.add(_Page.jobs);
          });
        },
      ),
      _Page.jobs => _MyJobs(
        repository: _repository,
        onChanged: _changed,
        onPostNew: () => _select(_Page.postJob),
      ),
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
        builder: (_) =>
            _JobDetail(repository: _repository, jobId: id, onChanged: _changed),
      ),
    );
  }

  Future<void> _openServiceReview(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ServiceReview(
          repository: _repository,
          jobId: id,
          onChanged: _changed,
        ),
      ),
    );
    _changed();
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({
    required this.repository,
    required this.onNavigate,
    required this.onOpenServiceReview,
  });

  final HouseholdRepository repository;
  final ValueChanged<_Page> onNavigate;
  final ValueChanged<int> onOpenServiceReview;

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
    setState(() => _future = _load());
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
        final pendingApplicants = jobs.fold<int>(
          0,
          (total, job) =>
              total +
              job.applications
                  .where((application) => application.status == 'pending')
                  .length,
        );
        final inProgressJobs = jobs.where(_isInProgressDashboardJob).length;
        final cancelledJobs = jobs
            .where((job) => _normalizedJobStatus(job.status) == 'cancelled')
            .length;
        final completedJobs = jobs
            .where((job) => _normalizedJobStatus(job.status) == 'completed')
            .length;
        final recentJobs = jobs.toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _HouseholdWelcomeBanner(profile: profile),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _HouseholdStatCard(
                      label: 'In Progress',
                      value: '$inProgressJobs',
                      icon: Icons.pending_actions_outlined,
                      highlighted: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HouseholdStatCard(
                      label: 'Cancelled',
                      value: '$cancelledJobs',
                      icon: Icons.cancel_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HouseholdStatCard(
                      label: 'Completed',
                      value: '$completedJobs',
                      icon: Icons.task_alt_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Recent Post Jobs',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: GawaGoColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (recentJobs.isEmpty)
                _HouseholdEmptyJobsCard(
                  onTap: () => widget.onNavigate(_Page.postJob),
                )
              else
                ...recentJobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RecentPostedJobCard(
                      job: job,
                      onTap: () => widget.onOpenServiceReview(job.id),
                    ),
                  ),
                ),
              if (pendingApplicants > 0) ...[
                const SizedBox(height: 4),
                _HouseholdNoticeCard(
                  message:
                      '$pendingApplicants pending ${pendingApplicants == 1 ? 'application' : 'applications'} need review.',
                  onTap: () => widget.onNavigate(_Page.jobs),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HouseholdWelcomeBanner extends StatelessWidget {
  const _HouseholdWelcomeBanner({required this.profile});

  final HouseholdProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: GawaGoColors.cardGreen,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F092F20),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Text(
        'Welcome, ${profile.fullName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _HouseholdStatCard extends StatelessWidget {
  const _HouseholdStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final labelColor = highlighted ? Colors.white : const Color(0xFF566279);
    final valueColor = highlighted ? Colors.white : const Color(0xFF001A4A);
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: highlighted ? GawaGoColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: highlighted
            ? null
            : Border.all(color: const Color(0xFFD8D0C3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: labelColor, size: 18),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: labelColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPostedJobCard extends StatelessWidget {
  const _RecentPostedJobCard({required this.job, required this.onTap});

  final HouseholdJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8D0C3), width: 1.2),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _JobInfoRow(label: 'Type', value: job.jobType),
              _JobInfoRow(label: 'Barangay', value: _barangay(job)),
              _JobInfoRow(label: 'Rate', value: _rateLabel(job)),
              _JobInfoRow(
                label: 'Status',
                valueWidget: Align(
                  alignment: Alignment.centerLeft,
                  child: _OpenStatusPill(status: job.status),
                ),
              ),
              _JobInfoRow(
                label: 'Applications',
                value: '${job.applications.length}',
                showDivider: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobInfoRow extends StatelessWidget {
  const _JobInfoRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Color(0xFFD8D0C3)))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 118,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF355444),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 11, 12, 11),
              child:
                  valueWidget ??
                  Text(
                    value ?? '',
                    style: const TextStyle(
                      color: Color(0xFF001A4A),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      height: 1.2,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenStatusPill extends StatelessWidget {
  const _OpenStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = _normalizedJobStatus(status);
    final isPositive =
        normalizedStatus == 'open' ||
        normalizedStatus == 'completed' ||
        normalizedStatus == 'cancelled';
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: isPositive ? const Color(0xFFE7F5E9) : const Color(0xFFF4F1EB),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isPositive ? const Color(0xFF9BD9A9) : const Color(0xFFD8D0C3),
          width: 1.4,
        ),
      ),
      child: Text(
        formatStatus(status),
        style: TextStyle(
          color: isPositive ? const Color(0xFF25853E) : const Color(0xFF566279),
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
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
      'completed' => GawaGoColors.primary,
      'cancelled' => const Color(0xFFE24A4A),
      'assigned' || 'completion_requested' => const Color(0xFF0A78A8),
      _ => const Color(0xFF25853E),
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

class _HouseholdNoticeCard extends StatelessWidget {
  const _HouseholdNoticeCard({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.info_outline),
      label: Text(message),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: GawaGoColors.panelGreen,
        side: const BorderSide(color: Color(0xFFBBD8C4)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
    'PHP ${job.serviceRate.toStringAsFixed(2)} / Per Day';

String _normalizedJobStatus(String status) => status
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

bool _isInProgressDashboardJob(HouseholdJob job) {
  return switch (_normalizedJobStatus(job.status)) {
    'assigned' ||
    'already found a worker' ||
    'in progress' ||
    'completion requested' ||
    'waiting for household confirmation' => true,
    _ => false,
  };
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
  });

  final HouseholdRepository repository;
  final VoidCallback onCreated;
  final VoidCallback onCancel;

  @override
  State<_PostJob> createState() => _PostJobState();
}

class _PostJobState extends State<_PostJob> {
  late final Future<HouseholdProfile> _profileFuture = widget.repository
      .getProfile();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _rate = TextEditingController();
  final _slots = TextEditingController(text: '1');
  String? _skill;
  String? _barangay;
  String _scheduleType = 'One-Time';
  String _rateType = 'Per Day';
  DateTime? _date;
  TimeOfDay? _time;
  LatLng? _pin;
  final List<String> _imagePaths = [];
  bool _posting = false;

  Future<void> _pickImages() async {
    const group = XTypeGroup(
      label: 'Job reference images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;
    final combined = {..._imagePaths, ...files.map((file) => file.path)};
    setState(() {
      _imagePaths
        ..clear()
        ..addAll(combined);
    });
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

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty ||
        _skill == null ||
        _barangay == null ||
        _date == null ||
        _time == null ||
        _location.text.trim().isEmpty ||
        _pin == null ||
        (double.tryParse(_rate.text) ?? 0) <= 0) {
      _message('Complete all required job, schedule, rate, and map fields.');
      return;
    }
    setState(() => _posting = true);
    try {
      final locationLabel = '${_barangay!}, ${_location.text.trim()}';
      await widget.repository.createJob({
        'title': _title.text.trim(),
        'job_type': _skill,
        'required_skill': _skill,
        'schedule_type': _scheduleType,
        'preferred_date': _date!.toIso8601String().split('T').first,
        'preferred_time': _clock(_time!),
        'description': _description.text.trim().isEmpty
            ? 'Rate type: $_rateType'
            : '${_description.text.trim()}\n\nRate type: $_rateType',
        'location_label': locationLabel,
        'latitude': _coordinateForApi(_pin!.latitude),
        'longitude': _coordinateForApi(_pin!.longitude),
        'service_rate': _rate.text.trim(),
        'worker_slots': int.tryParse(_slots.text) ?? 1,
      }, imagePaths: _imagePaths);
      widget.onCreated();
      if (mounted) _message('Job posted successfully.');
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
            onRetry: () => (context as Element).markNeedsBuild(),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final profile = snapshot.data!;
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
                      color: GawaGoColors.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
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
                        serviceType: _skill,
                        scheduleType: _scheduleType,
                        barangay: _barangay,
                        rateType: _rateType,
                        dateLabel: _date == null
                            ? 'mm/dd/yyyy'
                            : '${_date!.month.toString().padLeft(2, '0')}/${_date!.day.toString().padLeft(2, '0')}/${_date!.year}',
                        timeLabel: _time == null
                            ? '--:-- --'
                            : _time!.format(context),
                        onServiceChanged: (value) =>
                            setState(() => _skill = value),
                        onScheduleChanged: (value) => setState(
                          () => _scheduleType = value ?? _scheduleType,
                        ),
                        onBarangayChanged: (value) =>
                            setState(() => _barangay = value),
                        onRateTypeChanged: (value) =>
                            setState(() => _rateType = value ?? _rateType),
                        onPickDate: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (value != null) setState(() => _date = value);
                        },
                        onPickTime: () async {
                          final value = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (value != null) setState(() => _time = value);
                        },
                      );
                      final map = _PostJobMapPanel(
                        pin: _pin,
                        profilePin: profilePin,
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
                          backgroundColor: const Color(0xFF4CAF74),
                          foregroundColor: Colors.white,
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
                          foregroundColor: const Color(0xFF355444),
                          side: const BorderSide(color: Color(0xFFD8D0C3)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
    required this.serviceType,
    required this.scheduleType,
    required this.barangay,
    required this.rateType,
    required this.dateLabel,
    required this.timeLabel,
    required this.onServiceChanged,
    required this.onScheduleChanged,
    required this.onBarangayChanged,
    required this.onRateTypeChanged,
    required this.onPickDate,
    required this.onPickTime,
  });

  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController street;
  final TextEditingController rate;
  final TextEditingController slots;
  final String? serviceType;
  final String scheduleType;
  final String? barangay;
  final String rateType;
  final String dateLabel;
  final String timeLabel;
  final ValueChanged<String?> onServiceChanged;
  final ValueChanged<String?> onScheduleChanged;
  final ValueChanged<String?> onBarangayChanged;
  final ValueChanged<String?> onRateTypeChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

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
        _PostJobTwoColumn(
          left: _PostJobPickerField(
            label: 'Preferred Date',
            value: dateLabel,
            icon: Icons.calendar_today_outlined,
            onTap: onPickDate,
          ),
          right: _PostJobPickerField(
            label: 'Preferred Time',
            value: timeLabel,
            icon: Icons.schedule,
            onTap: onPickTime,
          ),
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
              items: const ['Per Day', 'Per Hour'],
              onChanged: onRateTypeChanged,
            ),
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
          color: Color(0xFF334C3C),
          fontSize: 16,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8DA0C4)),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: lines > 1 ? 14 : 12,
          ),
          filled: true,
          fillColor: const Color(0xFFF7F1E8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
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
          fillColor: const Color(0xFFF7F1E8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
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
        color: const Color(0xFFF7F1E8),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD8D0C3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF334C3C),
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
              color: Color(0xFF001A4A),
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

class _PostJobMapPanel extends StatelessWidget {
  const _PostJobMapPanel({
    required this.pin,
    required this.profilePin,
    required this.onSetPin,
    required this.onLocate,
  });

  final LatLng? pin;
  final LatLng? profilePin;
  final ValueChanged<LatLng> onSetPin;
  final VoidCallback onLocate;

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
              options: MapOptions(
                initialCenter:
                    pin ?? profilePin ?? const LatLng(12.8797, 121.7740),
                initialZoom: pin == null && profilePin == null ? 5.4 : 14,
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
                backgroundColor: const Color(0xFF4CAF74),
                foregroundColor: Colors.white,
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
                foregroundColor: const Color(0xFF355444),
                side: const BorderSide(color: Color(0xFFD8D0C3)),
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
                  foregroundColor: const Color(0xFF355444),
                  side: const BorderSide(color: Color(0xFFD8D0C3)),
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
            color: Color(0xFF001A4A),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD8D0C3)),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFA7B8FF),
                    width: 1.4,
                  ),
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
                        foregroundColor: const Color(0xFF355444),
                        side: const BorderSide(color: Color(0xFFD8D0C3)),
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
                  style: TextStyle(color: Color(0xFF355444)),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HouseholdJob>>(
      future: widget.repository.getMyJobs(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            error: snapshot.error,
            onRetry: () => (context as Element).markNeedsBuild(),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        if (snapshot.data!.isEmpty) {
          return const AppEmptyState(message: 'No jobs posted yet.');
        }
        final jobs = snapshot.data!;
        final visible = jobs.where((job) {
          if (_filter == 'all') return _isActiveHouseholdJob(job);
          if (_filter == 'open') return job.status == 'open';
          if (_filter == 'completed') return job.status == 'completed';
          return true;
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            const Text(
              'My Jobs',
              style: TextStyle(
                color: GawaGoColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD8D0C3), width: 1.2),
              ),
              child: Column(
                children: [
                  _MyJobsTabs(
                    selected: _filter,
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    _NoActiveJobsCard(
                      filter: _filter,
                      onPostNew: widget.onPostNew,
                    )
                  else
                    ...visible.map(
                      (job) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MyJobCard(
                          job: job,
                          onViewDetails: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _JobDetail(
                                  repository: widget.repository,
                                  jobId: job.id,
                                  onChanged: widget.onChanged,
                                ),
                              ),
                            );
                            widget.onChanged();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
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

bool _isActiveHouseholdJob(HouseholdJob job) {
  return switch (job.status.trim().toLowerCase()) {
    'open' || 'assigned' || 'in_progress' || 'completion_requested' => true,
    _ => false,
  };
}

class _NoActiveJobsCard extends StatelessWidget {
  const _NoActiveJobsCard({required this.filter, required this.onPostNew});

  final String filter;
  final VoidCallback onPostNew;

  @override
  Widget build(BuildContext context) {
    final isActiveView = filter == 'all' || filter == 'open';
    return _Card(
      child: Column(
        children: [
          Text(
            isActiveView ? 'No active jobs' : 'No $filter jobs',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isActiveView
                ? 'Completed and cancelled jobs are available in your dashboard recent jobs.'
                : 'Nothing matches this job status yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF355444),
              fontSize: 15,
              height: 1.35,
            ),
          ),
          if (isActiveView) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPostNew,
              icon: const Icon(Icons.post_add),
              label: const Text('Post a New Job'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyJobsTabs extends StatelessWidget {
  const _MyJobsTabs({required this.selected, required this.onChanged});

  final String selected;
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
          value: 'all',
          selected: selected == 'all',
          onChanged: onChanged,
        ),
        _MyJobsTabButton(
          label: 'Open',
          value: 'open',
          selected: selected == 'open',
          onChanged: onChanged,
        ),
        _MyJobsTabButton(
          label: 'Completed',
          value: 'completed',
          selected: selected == 'completed',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MyJobsTabButton extends StatelessWidget {
  const _MyJobsTabButton({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
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
          backgroundColor: selected ? GawaGoColors.cardGreen : Colors.white,
          foregroundColor: selected ? Colors.white : const Color(0xFF355444),
          side: const BorderSide(color: Color(0xFFD8D0C3), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MyJobCard extends StatelessWidget {
  const _MyJobCard({required this.job, required this.onViewDetails});

  final HouseholdJob job;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final pending = job.applications
        .where((application) => application.status == 'pending')
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JobStatusPill(status: job.status),
          const SizedBox(height: 12),
          Text(
            job.title,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _InlineJobMeta(label: 'Offer Rate:', value: _rateLabel(job)),
          _InlineJobMeta(label: 'Schedule:', value: _jobScheduleDisplay(job)),
          _InlineJobMeta(
            label: 'Applicants:',
            value: '${job.applications.length}',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: onViewDetails,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF74),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              child: const Text('View Details'),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFCFF5FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF81E5F1)),
            ),
            child: Text(
              'Hiring progress: ${job.hiredCount}/${job.workerSlots} worker(s) hired. Pending applications: $pending.',
              style: const TextStyle(
                color: Color(0xFF00505D),
                fontSize: 13,
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

class _InlineJobMeta extends StatelessWidget {
  const _InlineJobMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5F687A),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF001A4A),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
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
                onCancel: job.status == 'open' || job.status == 'assigned'
                    ? () => _run(
                        () => widget.repository.updateJobStatus(
                          job.id,
                          'cancelled',
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 26),
              _CompletionReviewPanel(
                job: job,
                busy: _busy,
                onConfirmCompleted:
                    job.status == 'completion_requested' ||
                        job.status == 'assigned'
                    ? () => _run(
                        () => widget.repository.updateJobStatus(
                          job.id,
                          'completed',
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 26),
              _ApplicantsPanel(
                job: job,
                repository: widget.repository,
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
            ],
          );
        },
      ),
    );
  }
}

class _JobDetailsSummaryCard extends StatelessWidget {
  const _JobDetailsSummaryCard({
    required this.job,
    required this.busy,
    required this.onCancel,
  });

  final HouseholdJob job;
  final bool busy;
  final VoidCallback? onCancel;

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
                  color: GawaGoColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
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
          _LargeDetailBox(
            label: 'Workers Needed',
            value: '${job.workerSlots} worker(s)',
          ),
          _LargeDetailBox(
            label: 'Hiring Status',
            value: '${job.hiredCount}/${job.workerSlots} Hired',
          ),
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

class _CompletionReviewPanel extends StatelessWidget {
  const _CompletionReviewPanel({
    required this.job,
    required this.busy,
    required this.onConfirmCompleted,
  });

  final HouseholdJob job;
  final bool busy;
  final VoidCallback? onConfirmCompleted;

  @override
  Widget build(BuildContext context) {
    final worker = _selectedWorker(job);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF74),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Completion & Review',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
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
                    color: GawaGoColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const _SmallLabel('Worker'),
                Text(
                  worker?.workerName ?? 'No worker selected',
                  style: const TextStyle(
                    color: Color(0xFF4A5E4F),
                    fontSize: 15,
                    height: 1.4,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const _SmallLabel('Status'),
                Text(
                  formatStatus(job.status),
                  style: const TextStyle(
                    color: Color(0xFF4A5E4F),
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
            ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFD8CDBB)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : onConfirmCompleted,
            style: FilledButton.styleFrom(
              backgroundColor: onConfirmCompleted == null
                  ? const Color(0xFFA4AAB0)
                  : const Color(0xFF4CAF74),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(fontSize: 14, letterSpacing: 0),
            ),
            child: Text(busy ? 'Confirming...' : 'Confirm Completed'),
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
  });

  final HouseholdJob job;
  final HouseholdRepository repository;
  final ValueChanged<HouseholdApplication> onOpenApplicant;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Applicants',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Workers who submitted an application for this job.',
            style: TextStyle(
              color: Color(0xFF244C3A),
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          if (job.applications.isEmpty)
            const _DashedEmptyBox(message: 'No worker applications yet.')
          else
            ...job.applications.map(
              (application) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ApplicantRow(
                  application: application,
                  onTap: () => onOpenApplicant(application),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
              color: GawaGoColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Suggested workers ranked by skill, verification status, distance, ratings, and service rate.',
            style: TextStyle(
              color: Color(0xFF244C3A),
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
                        child: _RecommendedWorkerRow(
                          worker: worker,
                          onHire: () async {
                            final existing = _applicationForWorker(job, worker);
                            if (worker.verificationStatus
                                    .trim()
                                    .toLowerCase() !=
                                'verified') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This worker must be verified before they can be hired.',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (job.hiredCount >= job.workerSlots) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This job already has enough hired workers.',
                                  ),
                                ),
                              );
                              return;
                            }
                            final existingStatus = existing?.status
                                .trim()
                                .toLowerCase();
                            if (existingStatus == 'hired') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This worker is already hired for this job.',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (existingStatus == 'hire_requested') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'A hire request was already sent to this worker.',
                                  ),
                                ),
                              );
                              return;
                            }
                            try {
                              if (existing != null) {
                                await repository.setApplicationStatus(
                                  existing.id,
                                  'hired',
                                );
                              } else {
                                await repository.sendHireRequest(
                                  job.id,
                                  worker.id,
                                );
                              }
                              onChanged();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      existing == null
                                          ? 'Hire request sent.'
                                          : 'Worker hired.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(friendlyApiError(error)),
                                  ),
                                );
                              }
                            }
                          },
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallLabel(label),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF001A4A),
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
        color: Color(0xFF5F687A),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF5F687A),
          fontSize: 14,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ApplicantRow extends StatelessWidget {
  const _ApplicantRow({required this.application, required this.onTap});

  final HouseholdApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8D0C3)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.person_outline, color: GawaGoColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.workerName,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      application.distanceKm == null
                          ? formatStatus(application.status)
                          : '${formatStatus(application.status)} | ${application.distanceKm!.toStringAsFixed(1)} km away',
                      style: const TextStyle(
                        color: Color(0xFF4A5E4F),
                        fontSize: 12,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedWorkerRow extends StatelessWidget {
  const _RecommendedWorkerRow({required this.worker, required this.onHire});

  final RecommendedWorker worker;
  final VoidCallback onHire;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF2EEE6),
                child: Text(
                  _initial(worker.username),
                  style: const TextStyle(
                    color: Color(0xFF4B6354),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusBadge(
                          status: worker.verificationStatus,
                          prefix: 'Verification',
                        ),
                        _SoftFactPill(worker.distanceLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CompactProfileFact(label: 'Rating', value: worker.ratingLabel),
          _CompactProfileFact(
            label: 'Match Score',
            value: worker.matchScore.toStringAsFixed(1),
          ),
          _CompactProfileFact(
            label: 'Skills',
            value: worker.skills.isEmpty
                ? 'No skills listed'
                : worker.skills.join(', '),
          ),
          if (worker.workerRate.isNotEmpty)
            _CompactProfileFact(label: 'Worker Rate', value: worker.workerRate),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onHire,
              icon: const Icon(Icons.person_add_alt_1),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF74),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              label: const Text(
                'Send Hire Request',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        color: const Color(0xFFFFFEFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1A2A1E),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Not available' : value,
            style: const TextStyle(
              color: Color(0xFF4A5E4F),
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

class _SoftFactPill extends StatelessWidget {
  const _SoftFactPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5EE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBBD8C4)),
      ),
      child: Text(
        label.isEmpty ? 'Distance unavailable' : label,
        style: const TextStyle(
          color: Color(0xFF25853E),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ApplicantProfileCard extends StatelessWidget {
  const _ApplicantProfileCard({
    required this.job,
    required this.application,
    required this.reviews,
  });

  final HouseholdJob job;
  final HouseholdApplication application;
  final List<GawaGoReview> reviews;

  @override
  Widget build(BuildContext context) {
    final feedback = reviews
        .where(
          (review) =>
              review.feedback.trim().isNotEmpty || review.rating != null,
        )
        .take(3)
        .toList();
    final workerName = application.workerName.isEmpty
        ? application.workerUsername
        : application.workerName;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFF2EEE6),
                backgroundImage: application.workerProfilePhotoUrl.isEmpty
                    ? null
                    : NetworkImage(application.workerProfilePhotoUrl),
                child: application.workerProfilePhotoUrl.isEmpty
                    ? Text(
                        _initial(workerName),
                        style: const TextStyle(
                          color: Color(0xFF4B6354),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${application.workerUsername}',
                      style: const TextStyle(
                        color: Color(0xFF4A5E4F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                status: application.workerVerificationStatus,
                prefix: 'Verification',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ApplicantProfileFact(
                  label: 'Rate',
                  value: application.workerRateLabel.isEmpty
                      ? 'Not disclosed'
                      : application.workerRateLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ApplicantProfileFact(
                  label: 'Rating',
                  value: application.workerRatingLabel,
                ),
              ),
              if (application.distanceKm != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _ApplicantProfileFact(
                    label: 'Distance',
                    value: '${application.distanceKm!.toStringAsFixed(1)} km',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _SmallLabel('Skills'),
          const SizedBox(height: 5),
          Text(
            application.workerSkills.isEmpty
                ? job.requiredSkill
                : application.workerSkills.join(', '),
            style: const TextStyle(
              color: Color(0xFF355444),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _SmallLabel('Experience'),
          const SizedBox(height: 5),
          Text(
            '${application.workerYearsExperience} year(s)',
            style: const TextStyle(color: Color(0xFF355444), fontSize: 14),
          ),
          if (application.workerBio.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SmallLabel('About the worker'),
            const SizedBox(height: 5),
            Text(
              application.workerBio,
              style: const TextStyle(
                color: Color(0xFF355444),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          if (application.note.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SmallLabel('Application Note'),
            const SizedBox(height: 5),
            Text(
              application.note,
              style: const TextStyle(
                color: Color(0xFF355444),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          const Text(
            'Recent Feedback',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (feedback.isEmpty)
            const Text(
              'No feedback submitted yet.',
              style: TextStyle(color: Color(0xFF5F687A), fontSize: 13),
            )
          else
            ...feedback.map((review) => _ApplicantFeedbackItem(review: review)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: application.status,
              prefix: 'Application',
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicantProfileFact extends StatelessWidget {
  const _ApplicantProfileFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SmallLabel(label),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? 'Not available' : value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF244C3A),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
      ],
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
                color: GawaGoColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (review.feedback.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              review.feedback,
              style: const TextStyle(
                color: Color(0xFF355444),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (review.jobTitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              review.jobTitle,
              style: const TextStyle(color: Color(0xFF5F687A), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceReview extends StatefulWidget {
  const _ServiceReview({
    required this.repository,
    required this.jobId,
    required this.onChanged,
  });

  final HouseholdRepository repository;
  final int jobId;
  final VoidCallback onChanged;

  @override
  State<_ServiceReview> createState() => _ServiceReviewState();
}

class _ServiceReviewState extends State<_ServiceReview> {
  late Future<HouseholdJob> _future = widget.repository.getJob(widget.jobId);
  bool _busy = false;
  bool _reviewOpen = false;
  double _rating = 5;
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = widget.repository.getJob(widget.jobId);
    });
    widget.onChanged();
  }

  Future<void> _confirmCompleted(HouseholdJob job) async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateJobStatus(job.id, 'completed');
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job marked as completed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReview(
    HouseholdJob job,
    HouseholdApplication application,
  ) async {
    setState(() => _busy = true);
    try {
      await widget.repository.reviewWorker(
        job,
        application,
        rating: _rating,
        feedback: _feedback.text.trim(),
      );
      _feedback.clear();
      setState(() => _reviewOpen = false);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Review submitted.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedDetailScaffold(
      title: 'Service Review',
      child: FutureBuilder<HouseholdJob>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ServiceReviewShell(
              title: 'Service Review',
              onClose: () => Navigator.pop(context),
              child: AppErrorState(error: snapshot.error, onRetry: _reload),
            );
          }
          if (!snapshot.hasData) {
            return _ServiceReviewShell(
              title: 'Service Review',
              onClose: () => Navigator.pop(context),
              child: const AppLoadingState(),
            );
          }
          final job = snapshot.data!;
          final selectedWorker = _selectedWorker(job);
          final canConfirm =
              selectedWorker != null &&
              (job.status == 'completion_requested' ||
                  job.status == 'assigned');
          final canReview =
              selectedWorker != null &&
              job.status == 'completed' &&
              job.canReview;
          return _ServiceReviewShell(
            title: job.title,
            onClose: () => Navigator.pop(context),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              children: [
                _WorkerReviewCard(job: job, application: selectedWorker),
                const SizedBox(height: 14),
                _JobReviewDetailsCard(job: job),
                const SizedBox(height: 14),
                _ServiceReviewProgressCard(
                  job: job,
                  application: selectedWorker,
                  reviewOpen: _reviewOpen,
                  rating: _rating,
                  feedback: _feedback,
                  busy: _busy,
                  onRatingChanged: (value) => setState(() => _rating = value),
                  onConfirmCompleted: canConfirm
                      ? () => _confirmCompleted(job)
                      : null,
                  onOpenReview: canReview
                      ? () => setState(() => _reviewOpen = true)
                      : null,
                  onSubmitReview: canReview
                      ? () => _submitReview(job, selectedWorker)
                      : null,
                  onDone: () => Navigator.pop(context),
                  onViewReviews: () {
                    Navigator.pop(context);
                    widget.onChanged();
                  },
                ),
                if (job.images.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ServiceReviewCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reference Images',
                          style: TextStyle(
                            color: GawaGoColors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        JobImageGallery(images: job.images),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ServiceReviewShell extends StatelessWidget {
  const _ServiceReviewShell({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: GawaGoColors.cream,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SERVICE REVIEW',
                    style: TextStyle(
                      color: GawaGoColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GawaGoColors.ink,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF355444),
                      side: const BorderSide(color: Color(0xFFD8D0C3)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFD8D0C3)),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _WorkerReviewCard extends StatelessWidget {
  const _WorkerReviewCard({required this.job, required this.application});

  final HouseholdJob job;
  final HouseholdApplication? application;

  @override
  Widget build(BuildContext context) {
    final hasWorker = application != null;
    final initial = hasWorker ? _initial(application!.workerName) : 'W';
    return _ServiceReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: const Color(0xFFF2EEE6),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF4B6354),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasWorker ? application!.workerName : 'No worker selected',
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasWorker
                ? 'Worker profile summary for this selected household job.'
                : 'Worker profile summary for this selected household job.',
            style: const TextStyle(
              color: Color(0xFF4A5E4F),
              fontSize: 15,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _ReviewInfoBox(
            label: 'Verification',
            value: hasWorker
                ? formatStatus(application!.workerVerificationStatus)
                : 'Not available',
          ),
          _ReviewInfoBox(
            label: 'Rating',
            value: hasWorker
                ? application!.workerRatingLabel
                : 'No ratings yet',
          ),
          _ReviewInfoBox(
            label: 'Skills',
            value: hasWorker && application!.workerSkills.isNotEmpty
                ? application!.workerSkills.join(', ')
                : job.requiredSkill,
          ),
          _ReviewInfoBox(
            label: 'Location',
            value: hasWorker && application!.locationLabel.isNotEmpty
                ? application!.locationLabel
                : _barangay(job),
          ),
          _ReviewInfoBox(
            label: 'Worker Rate',
            value: hasWorker && application!.workerRateLabel.isNotEmpty
                ? application!.workerRateLabel
                : _rateLabel(job),
          ),
          if (hasWorker && application!.distanceKm != null)
            _ReviewInfoBox(
              label: 'Distance',
              value: '${application!.distanceKm!.toStringAsFixed(1)} km away',
            ),
        ],
      ),
    );
  }
}

class _JobReviewDetailsCard extends StatelessWidget {
  const _JobReviewDetailsCard({required this.job});

  final HouseholdJob job;

  @override
  Widget build(BuildContext context) {
    return _ServiceReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Job Details',
            style: TextStyle(
              color: GawaGoColors.ink,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          _PlainDetail(label: 'Service', value: job.jobType),
          _PlainDetail(label: 'Rate', value: _rateLabel(job)),
          _PlainDetail(label: 'Schedule', value: _scheduleLabel(job.schedule)),
          _PlainDetail(label: 'Barangay', value: _barangay(job)),
          _PlainDetail(label: 'Status', value: formatStatus(job.status)),
          _PlainDetail(
            label: 'Applications',
            value: '${job.applications.length}',
          ),
          if (job.description.trim().isNotEmpty)
            _PlainDetail(label: 'Description', value: job.description.trim()),
        ],
      ),
    );
  }
}

class _ServiceReviewProgressCard extends StatelessWidget {
  const _ServiceReviewProgressCard({
    required this.job,
    required this.application,
    required this.reviewOpen,
    required this.rating,
    required this.feedback,
    required this.busy,
    required this.onRatingChanged,
    required this.onConfirmCompleted,
    required this.onOpenReview,
    required this.onSubmitReview,
    required this.onDone,
    required this.onViewReviews,
  });

  final HouseholdJob job;
  final HouseholdApplication? application;
  final bool reviewOpen;
  final double rating;
  final TextEditingController feedback;
  final bool busy;
  final ValueChanged<double> onRatingChanged;
  final VoidCallback? onConfirmCompleted;
  final VoidCallback? onOpenReview;
  final VoidCallback? onSubmitReview;
  final VoidCallback onDone;
  final VoidCallback onViewReviews;

  @override
  Widget build(BuildContext context) {
    final hasWorker = application != null;
    final status = job.status.trim().toLowerCase();
    final completed = status == 'completed';
    final waitingForHousehold = status == 'completion_requested';
    final reviewCompleted = completed && !job.canReview;
    final showReviewForm = reviewOpen && onSubmitReview != null;

    return _ServiceReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewNotice(
            message: completed
                ? 'Job is completed. You can review the worker profile and your submitted rating here.'
                : waitingForHousehold
                ? 'Worker marked this service as done. Confirm completion when the work is accepted.'
                : hasWorker
                ? 'Review the completed work, then confirm completion.'
                : 'No worker is assigned yet, so completion controls are not available.',
            success: reviewCompleted,
          ),
          const SizedBox(height: 20),
          _ReviewStep(
            number: 1,
            title: 'Worker hired',
            body: 'Job started after household accepted the worker.',
            done: hasWorker,
          ),
          _ReviewStep(
            number: 2,
            title: 'Worker requests completion',
            body: 'Worker marks service as done.',
            done: waitingForHousehold || completed,
            active: hasWorker && !waitingForHousehold && !completed,
          ),
          _ReviewStep(
            number: 3,
            title: 'Confirm completed',
            body: 'Household confirms completion.',
            done: completed,
            active: waitingForHousehold,
          ),
          _ReviewStep(
            number: 4,
            title: 'Rate worker',
            body: 'Household submits rating and feedback.',
            done: reviewCompleted,
            active: completed && !reviewCompleted,
          ),
          if (onConfirmCompleted != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onConfirmCompleted,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.task_alt),
                label: Text(busy ? 'Completing...' : 'Confirm Completed'),
              ),
            ),
          ],
          if (onOpenReview != null && !showReviewForm) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onOpenReview,
                icon: const Icon(Icons.star_outline),
                label: const Text('Rate Worker'),
              ),
            ),
          ],
          if (showReviewForm) ...[
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFD8CDBB)),
            const SizedBox(height: 12),
            const Text(
              'Rating for worker',
              style: TextStyle(
                color: Color(0xFF1A2A1E),
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: List.generate(5, (index) {
                final value = index + 1.0;
                return IconButton(
                  tooltip: '$value stars',
                  onPressed: busy ? null : () => onRatingChanged(value),
                  icon: Icon(
                    rating >= value ? Icons.star : Icons.star_border,
                    color: const Color(0xFFF0B429),
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedback,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Feedback for worker',
                hintText: 'Write feedback about the worker...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onSubmitReview,
                child: Text(busy ? 'Submitting...' : 'Submit Review'),
              ),
            ),
          ],
          if (reviewCompleted) ...[
            const SizedBox(height: 20),
            _ReviewNotice(
              message:
                  'Review completed. You rated this worker ${rating.toStringAsFixed(1)}/5.',
              success: true,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Text(
                      'Done',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onViewReviews,
                    child: const Text(
                      'View all Reviews',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.message, this.success = false});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE8F5E9) : const Color(0xFFFFF7E2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: success ? const Color(0xFF9BD9A9) : const Color(0xFFFFC04D),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: success ? const Color(0xFF25853E) : const Color(0xFF8A5B00),
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.number,
    required this.title,
    required this.body,
    this.done = false,
    this.active = false,
  });

  final int number;
  final String title;
  final String body;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFFBFEFD5)
        : active
        ? const Color(0xFF4CAF74)
        : const Color(0xFFF8F5EE);
    final textColor = active ? Colors.white : GawaGoColors.ink;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF4A5E4F),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF4A5E4F),
                    fontSize: 14,
                    height: 1.2,
                    letterSpacing: 0,
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

class _ServiceReviewCard extends StatelessWidget {
  const _ServiceReviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: child,
    );
  }
}

class _ReviewInfoBox extends StatelessWidget {
  const _ReviewInfoBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8CDBB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1A2A1E),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Not available' : value,
            style: const TextStyle(
              color: Color(0xFF4A5E4F),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainDetail extends StatelessWidget {
  const _PlainDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1A2A1E),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Not specified' : value,
            style: const TextStyle(
              color: Color(0xFF4A5E4F),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicantDetail extends StatelessWidget {
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

  Future<void> _action(BuildContext context, String status) async {
    try {
      await repository.setApplicationStatus(application.id, status);
      onChanged();
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  Future<void> _review(BuildContext context) async {
    double rating = 5;
    final feedback = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review Worker'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<double>(
                value: rating,
                items: [1, 2, 3, 4, 5]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value.toDouble(),
                        child: Text('$value stars'),
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
      try {
        await repository.reviewWorker(
          job,
          application,
          rating: rating,
          feedback: feedback.text,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
        }
      }
    }
    feedback.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (application.status == 'pending')
        FilledButton.icon(
          onPressed: () => _action(context, 'hired'),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Accept Applicant'),
        ),
      if (application.status == 'pending')
        OutlinedButton.icon(
          onPressed: () => _action(context, 'rejected'),
          icon: const Icon(Icons.close),
          label: const Text('Reject'),
        ),
      if (job.status == 'completed' &&
          application.status == 'completed' &&
          job.canReview)
        FilledButton.icon(
          onPressed: () => _review(context),
          icon: const Icon(Icons.star_outline),
          label: const Text('Review Worker'),
        ),
    ];
    return AuthenticatedDetailScaffold(
      title: 'Applicant Details',
      bottomNavigationBar: PersistentActionBar(children: actions),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          FutureBuilder<List<GawaGoReview>>(
            future: repository.getWorkerReviews(application.workerUsername),
            builder: (context, snapshot) {
              return _ApplicantProfileCard(
                job: job,
                application: application,
                reviews: snapshot.data ?? const [],
              );
            },
          ),
          const SizedBox(height: 20),
          LocationRouteMap(
            start:
                application.workerLatitude == null ||
                    application.workerLongitude == null
                ? null
                : LatLng(
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
        ],
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
  late final LatLng? _profilePin =
      widget.profile.latitude == null || widget.profile.longitude == null
      ? null
      : LatLng(widget.profile.latitude!, widget.profile.longitude!);
  String? _photoPath;
  bool _saving = false;

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
    if (_profilePin == null) {
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
        'phone': _phone.text.trim(),
        'location_label': [
          _barangay!,
          _street.text.trim(),
        ].where((part) => part.trim().isNotEmpty).join(', '),
        'latitude': _coordinateForApi(_profilePin.latitude),
        'longitude': _coordinateForApi(_profilePin.longitude),
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
            color: GawaGoColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
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
                        color: GawaGoColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${widget.profile.username}',
                      style: const TextStyle(
                        color: Color(0xFF5F687A),
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
                  color: Color(0xFF001A4A),
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
                style: TextStyle(color: Color(0xFF355444), fontSize: 13),
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
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF74),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
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
            color: GawaGoColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            decoration: const BoxDecoration(color: Color(0xFF4CAF74)),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
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
      backgroundColor: const Color(0xFFF2EEE6),
      backgroundImage: image,
      child: image == null
          ? Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF365B60),
                fontSize: 32,
                fontWeight: FontWeight.w900,
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
        color: const Color(0xFFE7F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9BD9A9)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF197A35),
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
      child: RichText(
        text: TextSpan(
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
        color: const Color(0xFFF7F1E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
              textStyle: const TextStyle(fontSize: 14, letterSpacing: 0),
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
                  color: Color(0xFF355444),
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
          color: Color(0xFF355444),
          fontSize: 14,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF7F1E8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
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
          fillColor: const Color(0xFFF7F1E8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD8D0C3)),
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
              color: Color(0xFF001A4A),
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
                color: GawaGoColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
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
                foregroundColor: const Color(0xFF197A35),
                backgroundColor: Colors.white,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
                    color: GawaGoColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                rating,
                style: const TextStyle(
                  color: GawaGoColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            review.feedback.isEmpty ? 'No written feedback.' : review.feedback,
            style: const TextStyle(
              color: Color(0xFF244C3A),
              fontSize: 18,
              height: 1.3,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formatLocalDateTime(review.createdAt, fallback: review.displayDate),
            style: const TextStyle(
              color: Color(0xFF244C3A),
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
    if (_primary == null || _secondary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose both required documents.')),
      );
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
              _VerificationDocumentPicker(
                title: 'Primary ID document',
                subtitle: 'Government-issued ID or a clear identity document.',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C3)),
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
      await widget.repository.markNotificationRead(item.id);
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
                  onSelected: (value) async {
                    if (value == 'details') {
                      await _viewDetails(item);
                    } else if (value == 'read') {
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
                  backgroundColor: const Color(0xFFF2EEE6),
                  child: Text(
                    _initial(application!.workerName),
                    style: const TextStyle(
                      color: Color(0xFF4B6354),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
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
                          color: GawaGoColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
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
              value: 'PHP ${job!.serviceRate.toStringAsFixed(2)} / Per Day',
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
      side: const BorderSide(color: Color(0xFFD8D0C3)),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

String _title(_Page page) => switch (page) {
  _Page.dashboard => 'Dashboard',
  _Page.postJob => 'Post a Job',
  _Page.jobs => 'My Jobs',
  _Page.profile => 'My Profile',
  _Page.reviews => 'Reviews & Feedback',
  _Page.verification => 'Get Verified',
  _Page.notifications => 'Notifications',
};

IconData _icon(_Page page) => switch (page) {
  _Page.dashboard => Icons.dashboard_outlined,
  _Page.postJob => Icons.post_add,
  _Page.jobs => Icons.work_outline,
  _Page.profile => Icons.person_outline,
  _Page.reviews => Icons.star_outline,
  _Page.verification => Icons.verified_outlined,
  _Page.notifications => Icons.notifications_none,
};

double _coordinateForApi(double value) =>
    double.parse(value.toStringAsFixed(7));

String _clock(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';
