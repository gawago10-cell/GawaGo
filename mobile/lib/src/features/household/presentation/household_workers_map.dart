import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/gawago_colors.dart';
import '../../../shared/utils/map_tile_guard.dart';
import '../../../shared/widgets/authenticated_shell.dart';
import '../data/household_models.dart';

const _tayabasCenter = LatLng(14.0269, 121.5926);
const _defaultZoom = 13.0;
const _otherPinColor = Color(0xFFC9C0A0);

/// Workers that share one ~1 km map cell. The backend snaps worker homes to
/// that grid, so several candidates often land on the same spot -- especially
/// on a 1 km job radius; one pin per spot keeps every worker reachable.
class WorkerMapArea {
  WorkerMapArea(this.point);

  final LatLng point;
  final List<RecommendedWorker> workers = [];

  String get key => '${point.latitude},${point.longitude}';
}

/// Groups [workers] by their approximate coordinates. Workers without any go
/// to [unmapped] so the screen can say they only appear in the list.
({List<WorkerMapArea> areas, List<RecommendedWorker> unmapped})
groupWorkersByMapArea(List<RecommendedWorker> workers) {
  final areas = <String, WorkerMapArea>{};
  final unmapped = <RecommendedWorker>[];
  for (final worker in workers) {
    final lat = worker.approximateLatitude;
    final lng = worker.approximateLongitude;
    if (lat == null || lng == null) {
      unmapped.add(worker);
      continue;
    }
    final area = areas.putIfAbsent(
      '$lat,$lng',
      () => WorkerMapArea(LatLng(lat, lng)),
    );
    area.workers.add(worker);
  }
  return (areas: areas.values.toList(), unmapped: unmapped);
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'W';
  if (parts.length == 1) {
    final single = parts.first;
    return (single.length == 1 ? single : single.substring(0, 2)).toUpperCase();
  }
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

/// Matched Workers "Map View": every matched worker pinned at their
/// approximate area around the job site. Tapping a pin lists the workers
/// available there with the same View Profile / Send Request actions as the
/// list.
class HouseholdWorkersMap extends StatefulWidget {
  const HouseholdWorkersMap({
    super.key,
    required this.workers,
    required this.onViewProfile,
    required this.onHire,
    this.jobLatitude,
    this.jobLongitude,
  });

  final List<RecommendedWorker> workers;
  final ValueChanged<RecommendedWorker> onViewProfile;
  final ValueChanged<RecommendedWorker> onHire;

  /// The household owns this job, so its site is their own address -- pinned
  /// exactly, unlike the candidates around it.
  final double? jobLatitude;
  final double? jobLongitude;

  @override
  State<HouseholdWorkersMap> createState() => _HouseholdWorkersMapState();
}

class _HouseholdWorkersMapState extends State<HouseholdWorkersMap> {
  final _controller = MapController();
  String? _selectedKey;

  LatLng? get _jobPoint =>
      widget.jobLatitude == null || widget.jobLongitude == null
      ? null
      : LatLng(widget.jobLatitude!, widget.jobLongitude!);

  void _showAll(List<WorkerMapArea> areas) {
    final points = [...areas.map((area) => area.point), ?_jobPoint];
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
      _controller.move(_jobPoint ?? _tayabasCenter, _defaultZoom);

  @override
  Widget build(BuildContext context) {
    final grouped = groupWorkersByMapArea(widget.workers);
    final areas = grouped.areas;
    WorkerMapArea? selected;
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
                    initialCenter: _jobPoint ?? _tayabasCenter,
                    initialZoom: _defaultZoom,
                    onTap: (_, _) => setState(() => _selectedKey = null),
                  ),
                  children: [
                    if (shouldLoadMapTiles) osmTileLayer(),
                    MarkerLayer(
                      markers: [
                        if (_jobPoint != null)
                          Marker(
                            point: _jobPoint!,
                            width: 46,
                            height: 24,
                            child: const _JobSiteMarker(),
                          ),
                        for (final area in areas)
                          Marker(
                            point: area.point,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: _WorkerPin(
                              area: area,
                              matches: area.workers.any(
                                (worker) => worker.matchesSkill,
                              ),
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
                        label: 'Show all workers',
                        onPressed: () => _showAll(areas),
                      ),
                      _MapControl(
                        label: _jobPoint == null
                            ? 'Tayabas City'
                            : 'My job site',
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
                      onViewProfile: widget.onViewProfile,
                      onHire: widget.onHire,
                      onClose: () => setState(() => _selectedKey = null),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _MapLegend(
          showJob: _jobPoint != null,
          unmappedCount: grouped.unmapped.length,
        ),
      ],
    );
  }
}

class _WorkerPin extends StatelessWidget {
  const _WorkerPin({
    required this.area,
    required this.matches,
    required this.selected,
    required this.onTap,
  });

  final WorkerMapArea area;
  final bool matches;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = area.workers.length == 1
        ? _initials(area.workers.first.displayName)
        : '${area.workers.length}';
    final names = area.workers
        .map((worker) => worker.displayName)
        .toSet()
        .join(', ');
    return Semantics(
      button: true,
      label:
          '${area.workers.length} worker${area.workers.length == 1 ? '' : 's'} '
          'in this area: $names',
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

class _JobSiteMarker extends StatelessWidget {
  const _JobSiteMarker();

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
        'Job',
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
    required this.onViewProfile,
    required this.onHire,
    required this.onClose,
  });

  final WorkerMapArea area;
  final ValueChanged<RecommendedWorker> onViewProfile;
  final ValueChanged<RecommendedWorker> onHire;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final count = area.workers.length;
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
                          ? '1 worker in this area'
                          : '$count workers in this area',
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
                  final worker = area.workers[index];
                  return _AreaWorkerTile(
                    worker: worker,
                    onViewProfile: () => onViewProfile(worker),
                    onHire: () => onHire(worker),
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

class _AreaWorkerTile extends StatelessWidget {
  const _AreaWorkerTile({
    required this.worker,
    required this.onViewProfile,
    required this.onHire,
  });

  final RecommendedWorker worker;
  final VoidCallback onViewProfile;
  final VoidCallback onHire;

  @override
  Widget build(BuildContext context) {
    final verified = worker.verificationStatus.toLowerCase() == 'verified';
    final matches = worker.matchesSkill;
    final meta = [
      if (worker.ratingLabel.isNotEmpty) worker.ratingLabel,
      if (worker.locationLabel.isNotEmpty)
        worker.locationLabel.split(',').first,
      if (worker.distanceLabel.isNotEmpty) worker.distanceLabel,
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
                  _initials(worker.displayName),
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
                      worker.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GawaGoColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      verified ? '✓ Verified worker' : 'Unverified worker',
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
                  matches ? 'Matches Skills' : 'Other Worker',
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
                  worker.skills.isEmpty
                      ? 'No skills listed'
                      : worker.skills.take(2).join(', '),
                  style: gawagoHeading(fontSize: 16),
                ),
              ),
              if (worker.workerRate.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '₱${worker.workerRate}',
                        style: const TextStyle(
                          fontFamily: GawaGoColors.fontHeading,
                          color: GawaGoColors.leafDeep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(
                        text: '/day',
                        style: TextStyle(
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
                  onPressed: onViewProfile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GawaGoColors.ink,
                    side: const BorderSide(
                      color: GawaGoColors.lineStrong,
                      width: 1.5,
                    ),
                  ),
                  child: const Text('View Profile'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onHire,
                  child: const Text('Send Request'),
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
  const _MapLegend({required this.showJob, required this.unmappedCount});

  final bool showJob;
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
              dot(GawaGoColors.primary, "Matches the job's skill"),
              dot(_otherPinColor, 'Other matched workers'),
              if (showJob) dot(GawaGoColors.sidebar, 'Your job site'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pins mark the general area (about 1 km) to keep the map '
            'readable. Once a worker applies, their applicant card shows '
            'their exact location and route.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          if (unmappedCount > 0)
            Text(
              unmappedCount == 1
                  ? '1 worker has no map location yet and appears only in List View.'
                  : '$unmappedCount workers have no map location yet and appear '
                        'only in List View.',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}
