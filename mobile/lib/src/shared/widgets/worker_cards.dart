import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

const _gold = Color(0xFFE0A82E);
const _cardBorder = Color(0xFFD8D0C3);

/// Circular match meter: the share of a worker's content-based fit, drawn the
/// same way on the AI match cards and the applicant cards so one number means
/// one thing everywhere.
class WorkerMatchRing extends StatelessWidget {
  const WorkerMatchRing({
    super.key,
    required this.score,
    this.size = 46,
    this.onPhoto = false,
  });

  /// 0-1 content-based score.
  final double score;
  final double size;

  /// Over a photo the label sits on a dark backdrop, so it flips to white
  /// instead of the ring's own colour.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final percent = (score.clamp(0, 1) * 100).round();
    final strong = percent >= 85;
    final color = strong ? GawaGoColors.primary : _gold;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 4,
              backgroundColor: onPhoto
                  ? Colors.white.withValues(alpha: 0.35)
                  : const Color(0xFFE6E0D5),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '$percent%',
            style: TextStyle(
              color: onPhoto ? Colors.white : color,
              fontSize: size * 0.24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five stars plus the numeric rating and review count. Falls back to
/// "No ratings yet" so a new worker doesn't read as a zero-star one.
class WorkerStarRow extends StatelessWidget {
  const WorkerStarRow({
    super.key,
    required this.ratingLabel,
    required this.ratingCount,
    this.starSize = 13,
  });

  final String ratingLabel;
  final int ratingCount;
  final double starSize;

  static double? parseRating(String label) {
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(label);
    if (match == null) return null;
    final value = double.tryParse(match.group(0)!);
    return value != null && value > 0 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final value = parseRating(ratingLabel);
    if (value == null) {
      return const Text(
        'No ratings yet',
        style: TextStyle(color: GawaGoColors.textMuted, fontSize: 12),
      );
    }
    final rounded = value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(
          5,
          (index) => Icon(
            index < rounded ? Icons.star_rounded : Icons.star_border_rounded,
            size: starSize + 3,
            color: _gold,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (ratingCount > 0) ...[
          const SizedBox(width: 3),
          Text(
            '($ratingCount)',
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// A worker's photo, falling back to their initials whenever there is no
/// photo on file or the image can't be fetched.
class WorkerPhoto extends StatelessWidget {
  const WorkerPhoto({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.size,
    this.radius = 999,
    this.fontSize,
  });

  final String photoUrl;
  final String name;
  final double size;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: GawaGoColors.primary,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize ?? size * 0.36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: photoUrl.trim().isEmpty
            ? fallback
            : Image.network(
                photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'W';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class _SkillChips extends StatelessWidget {
  const _SkillChips({required this.skills, this.visible = 2});

  final List<String> skills;
  final int visible;

  @override
  Widget build(BuildContext context) {
    final extra = skills.length - visible;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...skills
            .take(visible)
            .map((skill) => _Chip(label: skill, muted: false)),
        if (extra > 0) _Chip(label: '+$extra', muted: true),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.muted});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1EFE8) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? GawaGoColors.textMuted : GawaGoColors.primary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The photo-topped card the AI match list is built from.
class WorkerMatchCard extends StatelessWidget {
  const WorkerMatchCard({
    super.key,
    required this.name,
    required this.locationLabel,
    required this.photoUrl,
    required this.verified,
    required this.matchScore,
    required this.ratingLabel,
    required this.ratingCount,
    required this.distanceLabel,
    required this.completedJobs,
    required this.rateLabel,
    required this.skills,
    required this.bio,
    required this.onViewProfile,
    required this.onSendRequest,
    this.requestSent = false,
  });

  final String name;
  final String locationLabel;
  final String photoUrl;
  final bool verified;
  final double matchScore;
  final String ratingLabel;
  final int ratingCount;
  final String distanceLabel;
  final int completedJobs;
  final String rateLabel;
  final List<String> skills;
  final String bio;
  final VoidCallback onViewProfile;
  final VoidCallback onSendRequest;
  final bool requestSent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4:3 at phone width, but capped so a wide window (tablet, or the
          // web build) doesn't turn the photo into the whole card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PhotoBackdrop(photoUrl: photoUrl, name: name),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x520F2D1F),
                          Color(0x000F2D1F),
                          Color(0xC70F2D1F),
                        ],
                        stops: [0, 0.38, 1],
                      ),
                    ),
                  ),
                  if (verified)
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: _DarkPill(label: '✓ Verified'),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: WorkerMatchRing(
                      score: matchScore,
                      size: 46,
                      onPhoto: true,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                locationLabel.isEmpty
                                    ? 'Location not set'
                                    : locationLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (rateLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _DarkPill(label: rateLabel, radius: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    WorkerStarRow(
                      ratingLabel: ratingLabel,
                      ratingCount: ratingCount,
                    ),
                    Text(
                      '· $distanceLabel',
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '· $completedJobs ${completedJobs == 1 ? 'job' : 'jobs'}',
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SkillChips(skills: skills),
                ],
                if (bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    bio.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onViewProfile,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GawaGoColors.ink,
                          side: const BorderSide(color: _cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'View Profile',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: requestSent ? null : onSendRequest,
                        style: FilledButton.styleFrom(
                          backgroundColor: GawaGoColors.deepGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          requestSent ? 'Request Sent' : 'Send a Request',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
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

class _PhotoBackdrop extends StatelessWidget {
  const _PhotoBackdrop({required this.photoUrl, required this.name});

  final String photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: GawaGoColors.deepGreen,
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    if (photoUrl.trim().isEmpty) return fallback;
    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.label, this.radius = 999});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xD90F2D1F),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One applicant in the "Applicants" modal: the same worker facts as a match
/// card, plus the three responses a household can give.
class ApplicantCard extends StatelessWidget {
  const ApplicantCard({
    super.key,
    required this.name,
    required this.locationLabel,
    required this.photoUrl,
    required this.verified,
    required this.matchScore,
    required this.ratingLabel,
    required this.ratingCount,
    required this.rateLabel,
    required this.completedJobs,
    required this.skills,
    required this.bio,
    required this.appliedAgo,
    required this.isTopMatch,
    required this.statusLabel,
    required this.onDecline,
    required this.onViewProfile,
    required this.onSendRequest,
  });

  final String name;
  final String locationLabel;
  final String photoUrl;
  final bool verified;
  final double? matchScore;
  final String ratingLabel;
  final int ratingCount;
  final String rateLabel;
  final int completedJobs;
  final List<String> skills;
  final String bio;
  final String appliedAgo;
  final bool isTopMatch;

  /// "Hired"/"Hire Requested" etc. -- when set, the responses are spent and
  /// only the profile stays reachable.
  final String? statusLabel;
  final VoidCallback onDecline;
  final VoidCallback onViewProfile;
  final VoidCallback onSendRequest;

  @override
  Widget build(BuildContext context) {
    final settled = statusLabel != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    WorkerPhoto(
                      photoUrl: photoUrl,
                      name: name,
                      size: 54,
                      radius: 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: GawaGoColors.ink,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            locationLabel.isEmpty
                                ? 'Location not set'
                                : locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: GawaGoColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (matchScore != null) ...[
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          WorkerMatchRing(score: matchScore!, size: 48),
                          const SizedBox(height: 2),
                          const Text(
                            'match',
                            style: TextStyle(
                              color: GawaGoColors.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (verified)
                      const CircleAvatar(
                        radius: 9,
                        backgroundColor: GawaGoColors.primary,
                        child: Icon(Icons.check, size: 11, color: Colors.white),
                      ),
                    WorkerStarRow(
                      ratingLabel: ratingLabel,
                      ratingCount: ratingCount,
                    ),
                    if (rateLabel.isNotEmpty)
                      Text(
                        rateLabel,
                        style: const TextStyle(
                          color: GawaGoColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      '$completedJobs ${completedJobs == 1 ? 'job' : 'jobs'}',
                      style: const TextStyle(
                        color: GawaGoColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SkillChips(skills: skills, visible: 3),
                ],
                if (bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    bio.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GawaGoColors.textMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appliedAgo.isEmpty ? 'Applied' : 'Applied $appliedAgo',
                        style: const TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    if (isTopMatch) const _SoftPill(label: 'Top match'),
                    if (settled) ...[
                      if (isTopMatch) const SizedBox(width: 6),
                      _SoftPill(label: statusLabel!),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _cardBorder),
          IntrinsicHeight(
            child: Row(
              children: [
                if (!settled) ...[
                  Expanded(
                    child: _CardAction(label: 'Decline', onPressed: onDecline),
                  ),
                  const VerticalDivider(width: 1, color: _cardBorder),
                ],
                Expanded(
                  child: _CardAction(
                    label: 'View Profile',
                    onPressed: onViewProfile,
                  ),
                ),
                if (!settled) ...[
                  const VerticalDivider(width: 1, color: _cardBorder),
                  Expanded(
                    child: _CardAction(
                      label: 'Send a Request',
                      onPressed: onSendRequest,
                      filled: true,
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

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? GawaGoColors.deepGreen : Colors.white,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled ? Colors.white : GawaGoColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GawaGoColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
