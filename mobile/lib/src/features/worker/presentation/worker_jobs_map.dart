import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/gawago_colors.dart';
import '../../../shared/utils/map_tile_guard.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../data/worker_models.dart';

const _tayabasCenter = LatLng(14.0269, 121.5926);
const _defaultZoom = 13.0;
const _otherPinColor = Color(0xFFC9C0A0);

/// Jobs that share one ~1 km map cell. The backend snaps job sites to that
/// grid, so several jobs often land on the same spot; one pin per spot keeps
/// every job reachable.
class JobMapArea {
  JobMapArea(this.point);

  final LatLng point;
  final List<WorkerJob> jobs = [];

  String get key => '${point.latitude},${point.longitude}';
}

/// Groups [jobs] by their approximate coordinates. Jobs without any go to
/// [unmapped] so the screen can say they only appear in the list.
({List<JobMapArea> areas, List<WorkerJob> unmapped}) groupJobsByMapArea(
  List<WorkerJob> jobs,
) {
  final areas = <String, JobMapArea>{};
  final unmapped = <WorkerJob>[];
  for (final job in jobs) {
    final lat = job.approximateLatitude;
    final lng = job.approximateLongitude;
    if (lat == null || lng == null) {
      unmapped.add(job);
      continue;
    }
    final area = areas.putIfAbsent(
      '$lat,$lng',
      () => JobMapArea(LatLng(lat, lng)),
    );
    area.jobs.add(job);
  }
  return (areas: areas.values.toList(), unmapped: unmapped);
}

String _initials(String name) {
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

/// Find Jobs "Map View": every open job pinned at its approximate area, near
/// or far, matching the worker's skills or not. Tapping a pin lists the jobs
/// posted there with the same View Details / Apply actions as the list.
class WorkerJobsMap extends StatefulWidget {
  const WorkerJobsMap({
    super.key,
    required this.jobs,
    required this.matchesSkills,
    required this.distanceLabel,
    required this.onViewDetails,
    required this.onApply,
    this.workerLatitude,
    this.workerLongitude,
  });

  final List<WorkerJob> jobs;
  final bool Function(WorkerJob job) matchesSkills;
  final String Function(WorkerJob job) distanceLabel;
  final ValueChanged<WorkerJob> onViewDetails;
  final ValueChanged<WorkerJob> onApply;
  final double? workerLatitude;
  final double? workerLongitude;

  @override
  State<WorkerJobsMap> createState() => _WorkerJobsMapState();
}

class _WorkerJobsMapState extends State<WorkerJobsMap> {
  final _controller = MapController();
  String? _selectedKey;

  LatLng? get _workerPoint =>
      widget.workerLatitude == null || widget.workerLongitude == null
      ? null
      : LatLng(widget.workerLatitude!, widget.workerLongitude!);

  void _showAll(List<JobMapArea> areas) {
    final points = [...areas.map((area) => area.point), ?_workerPoint];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller.move(points.first, _defaultZoom);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        maxZoom: 15,
      ),
    );
  }

  void _recenter() =>
      _controller.move(_workerPoint ?? _tayabasCenter, _defaultZoom);

  @override
  Widget build(BuildContext context) {
    final grouped = groupJobsByMapArea(widget.jobs);
    final areas = grouped.areas;
    JobMapArea? selected;
    for (final area in areas) {
      if (area.key == _selectedKey) selected = area;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _workerPoint ?? _tayabasCenter,
                    initialZoom: _defaultZoom,
                    onTap: (_, _) => setState(() => _selectedKey = null),
                  ),
                  children: [
                    if (shouldLoadMapTiles) osmTileLayer(),
                    MarkerLayer(
                      markers: [
                        if (_workerPoint != null)
                          Marker(
                            point: _workerPoint!,
                            width: 46,
                            height: 24,
                            child: const _YouMarker(),
                          ),
                        for (final area in areas)
                          Marker(
                            point: area.point,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: _JobPin(
                              area: area,
                              matches: area.jobs.any(widget.matchesSkills),
                              selected: area.key == _selectedKey,
                              onTap: () => setState(
                                () => _selectedKey = _selectedKey == area.key
                                    ? null
                                    : area.key,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Wrap(
                    spacing: 6,
                    children: [
                      _MapControl(
                        label: 'Show all jobs',
                        onPressed: () => _showAll(areas),
                      ),
                      _MapControl(
                        label: _workerPoint == null
                            ? 'Tayabas City'
                            : 'Near me',
                        onPressed: _recenter,
                      ),
                    ],
                  ),
                ),
                if (selected != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _AreaPanel(
                      area: selected,
                      matchesSkills: widget.matchesSkills,
                      distanceLabel: widget.distanceLabel,
                      onViewDetails: widget.onViewDetails,
                      onApply: widget.onApply,
                      onClose: () => setState(() => _selectedKey = null),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _MapLegend(
          showWorker: _workerPoint != null,
          unmappedCount: grouped.unmapped.length,
        ),
      ],
    );
  }
}

class _JobPin extends StatelessWidget {
  const _JobPin({
    required this.area,
    required this.matches,
    required this.selected,
    required this.onTap,
  });

  final JobMapArea area;
  final bool matches;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final households = area.jobs.map((job) => job.householdUsername).toSet();
    final label = households.length == 1 && area.jobs.length == 1
        ? _initials(area.jobs.first.householdName)
        : '${area.jobs.length}';
    final names = area.jobs.map((job) => job.householdName).toSet().join(', ');
    return Semantics(
      button: true,
      label:
          '${area.jobs.length} job${area.jobs.length == 1 ? '' : 's'} by $names',
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 120),
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: matches ? GawaGoColors.primary : _otherPinColor,
                  border: Border.all(
                    color: selected ? GawaGoColors.ink : GawaGoColors.surface,
                    width: 2.5,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(19),
                    topRight: Radius.circular(19),
                    bottomRight: Radius.circular(19),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D1F2A19),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: GawaGoColors.fontHeading,
                      color: matches
                          ? GawaGoColors.onPrimary
                          : const Color(0xFF4D4735),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YouMarker extends StatelessWidget {
  const _YouMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GawaGoColors.sidebar,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GawaGoColors.surface, width: 2),
      ),
      child: const Text(
        'You',
        style: TextStyle(
          color: GawaGoColors.cream,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GawaGoColors.surface,
      shape: const StadiumBorder(
        side: BorderSide(color: GawaGoColors.lineStrong),
      ),
      elevation: 2,
      shadowColor: const Color(0x331F2A19),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: const TextStyle(
              color: GawaGoColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaPanel extends StatelessWidget {
  const _AreaPanel({
    required this.area,
    required this.matchesSkills,
    required this.distanceLabel,
    required this.onViewDetails,
    required this.onApply,
    required this.onClose,
  });

  final JobMapArea area;
  final bool Function(WorkerJob job) matchesSkills;
  final String Function(WorkerJob job) distanceLabel;
  final ValueChanged<WorkerJob> onViewDetails;
  final ValueChanged<WorkerJob> onApply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final count = area.jobs.length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.42,
      ),
      child: Material(
        color: GawaGoColors.surface,
        elevation: 10,
        shadowColor: const Color(0x521F2A19),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: GawaGoColors.sidebar,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      count == 1
                          ? '1 job in this area'
                          : '$count jobs in this area',
                      style: const TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        color: GawaGoColors.cream,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: GawaGoColors.cream),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: count,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: GawaGoColors.line),
                itemBuilder: (context, index) {
                  final job = area.jobs[index];
                  return _AreaJobTile(
                    job: job,
                    matches: matchesSkills(job),
                    distance: distanceLabel(job),
                    onViewDetails: () => onViewDetails(job),
                    onApply: () => onApply(job),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaJobTile extends StatelessWidget {
  const _AreaJobTile({
    required this.job,
    required this.matches,
    required this.distance,
    required this.onViewDetails,
    required this.onApply,
  });

  final WorkerJob job;
  final bool matches;
  final String distance;
  final VoidCallback onViewDetails;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final verified =
        job.householdVerificationStatus.toLowerCase() == 'verified';
    final meta = [
      if (job.requiredSkill.isNotEmpty) job.requiredSkill,
      if (job.locationLabel.isNotEmpty) job.locationLabel.split(',').first,
      distance,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GawaGoColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _initials(job.householdName),
                  style: const TextStyle(
                    fontFamily: GawaGoColors.fontHeading,
                    color: GawaGoColors.onPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.householdName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      verified
                          ? '✓ Verified household'
                          : 'Unverified household',
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: matches ? const Color(0x249EBF5E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: matches
                        ? GawaGoColors.leafLine
                        : GawaGoColors.lineStrong,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  matches ? 'Matches Skills' : 'Other Job',
                  style: TextStyle(
                    color: matches
                        ? GawaGoColors.leafDeep
                        : GawaGoColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  job.title.isEmpty ? job.requiredSkill : job.title,
                  style: gawagoHeading(fontSize: 16),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '₱${job.serviceRate.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        color: GawaGoColors.leafDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: '/${job.rateTypeLabel.toLowerCase()}',
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
          const SizedBox(height: 4),
          Text(
            meta,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewDetails,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.ink,
                    side: const BorderSide(
                      color: GawaGoColors.lineStrong,
                      width: 1.5,
                    ),
                  ),
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: job.canApply ? onApply : null,
                  child: Text(job.canApply ? 'Apply Now' : 'Applied'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.showWorker, required this.unmappedCount});

  final bool showWorker;
  final int unmappedCount;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: GawaGoColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              dot(GawaGoColors.primary, 'Matches your skills'),
              dot(_otherPinColor, 'Other jobs'),
              if (showWorker) dot(GawaGoColors.sidebar, 'Your location'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pins mark the general area (about 1 km) to keep the map '
            'readable. Open a job to see its exact location and the route '
            'from your place.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          if (unmappedCount > 0)
            Text(
              unmappedCount == 1
                  ? '1 job has no map location yet and appears only in List View.'
                  : '$unmappedCount jobs have no map location yet and appear only '
                        'in List View.',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}
