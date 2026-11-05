import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../../features/worker/data/worker_models.dart';
import '../utils/display_formatters.dart';
import 'authenticated_image.dart';
import 'profile_section.dart';

/// Portfolio pieces shared by the worker's own Skills & Portfolio tab and the
/// worker profile a household opens, so both sides see the same certificate
/// details, work samples and job ratings. Matches the web's
/// PortfolioSections.jsx (2026-11-05).

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  const months = [
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
  ];
  final local = parsed.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

class PortfolioCertificateCard extends StatelessWidget {
  const PortfolioCertificateCard({
    super.key,
    required this.certificate,
    this.showRejectReason = false,
    this.trailing,
  });

  final WorkerCertificate certificate;

  /// Only the worker sees why an admin turned a certificate down.
  final bool showRejectReason;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (certificate.issuer.isNotEmpty) certificate.issuer,
      if (certificate.issueDate.isNotEmpty)
        'Issued ${_shortDate(certificate.issueDate)}',
      if (certificate.expiryDate.isNotEmpty)
        'Expires ${_shortDate(certificate.expiryDate)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GawaGoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The file route needs the bearer token, which Image.network
          // can't send; PDFs get a pointer to the website instead.
          if (certificate.fileUrl.isNotEmpty && certificate.isImage)
            AuthenticatedImage(url: certificate.fileUrl, height: 150)
          else if (certificate.fileUrl.isNotEmpty)
            CertificateFileNote(isPdf: certificate.isPdf),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
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
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta.join(' · '),
                          style: const TextStyle(
                            color: GawaGoColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
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
                      if (showRejectReason &&
                          certificate.verificationStatus == 'rejected' &&
                          certificate.verificationNotes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Reason: ${certificate.verificationNotes}',
                          style: const TextStyle(
                            color: GawaGoColors.danger,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A before/after pair when both photos exist, otherwise the one photo the
/// sample was saved with.
class PortfolioWorkSampleCard extends StatelessWidget {
  const PortfolioWorkSampleCard({
    super.key,
    required this.sample,
    this.actions,
  });

  final WorkSample sample;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final before = sample.beforeOrFallback;
    final after = sample.afterImageUrl;
    final pair = before.isNotEmpty && after.isNotEmpty;
    final single = before.isNotEmpty ? before : after;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GawaGoColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
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
          if (pair)
            Row(
              children: [
                Expanded(
                  child: _SamplePhoto(url: before, tag: 'Before'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SamplePhoto(url: after, tag: 'After', leaf: true),
                ),
              ],
            )
          else if (single.isNotEmpty)
            _SamplePhoto(url: single, height: 160)
          else
            const Text(
              'No photo',
              style: TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
            ),
          if (actions != null) ...[const SizedBox(height: 12), actions!],
        ],
      ),
    );
  }
}

class _SamplePhoto extends StatelessWidget {
  const _SamplePhoto({
    required this.url,
    this.tag,
    this.leaf = false,
    this.height = 120,
  });

  final String url;
  final String? tag;
  final bool leaf;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: GawaGoColors.border),
            ),
            if (tag != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: leaf ? GawaGoColors.leafDeep : GawaGoColors.ink,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One completed job: the household's own rating of the worker as the job's
/// overall (the review that counts toward the worker's reputation), with the
/// per-skill ratings -- or the household's metric ratings -- as bars.
class EmploymentHistoryCard extends StatelessWidget {
  const EmploymentHistoryCard({
    super.key,
    required this.title,
    required this.householdName,
    required this.locationLabel,
    required this.completedAt,
    required this.skillRatings,
    required this.householdRating,
  });

  final String title;
  final String householdName;
  final String locationLabel;
  final String completedAt;
  final List<JobSkillRating> skillRatings;
  final JobHouseholdRating? householdRating;

  @override
  Widget build(BuildContext context) {
    final review = householdRating;
    final bars = skillRatings.isNotEmpty
        ? [
            for (final item in skillRatings)
              MapEntry(item.skillName, item.rating),
          ]
        : (review?.metrics ?? const <MapEntry<String, double>>[]);
    final where = [
      householdName.isEmpty ? 'Household' : householdName,
      if (locationLabel.isNotEmpty) locationLabel,
    ].join(' · ');
    return Container(
      key: const Key('employment-history-card'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            where,
            style: const TextStyle(color: GawaGoColors.textMuted, fontSize: 13),
          ),
          if (completedAt.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Completed ${_shortDate(completedAt)}',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 78,
                // Grows with large system text instead of overflowing.
                constraints: const BoxConstraints(minHeight: 78),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: review == null
                      ? GawaGoColors.surfaceMuted
                      : GawaGoColors.ink,
                  borderRadius: BorderRadius.circular(14),
                  border: review == null
                      ? Border.all(color: GawaGoColors.lineStrong)
                      : null,
                ),
                child: review == null
                    ? const Text(
                        'Not rated\nyet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 11.5,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            review.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: GawaGoColors.fontHeading,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'overall ★',
                            style: TextStyle(
                              color: Color(0xFFE6EFD2),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: bars.isNotEmpty
                    ? Column(
                        children: [
                          for (final bar in bars) _RatingBar(entry: bar),
                        ],
                      )
                    : Text(
                        review == null
                            ? "Waiting for the household's rating."
                            : review.isDefault
                            ? "Automatic 3.5 rating: the household didn't rate this job in time."
                            : 'The household gave an overall rating only.',
                        style: const TextStyle(
                          color: GawaGoColors.textMuted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.entry});

  final MapEntry<String, double> entry;

  @override
  Widget build(BuildContext context) {
    final value = entry.value.clamp(0, 5).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Text(
              entry.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / 5,
                minHeight: 7,
                backgroundColor: GawaGoColors.inputBorder,
                color: GawaGoColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text(
              value == value.roundToDouble()
                  ? value.toStringAsFixed(0)
                  : value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: GawaGoColors.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
