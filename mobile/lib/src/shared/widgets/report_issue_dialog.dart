import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/errors/api_error.dart';
import '../../core/theme/gawago_colors.dart';
import '../../features/complaints/data/complaint_models.dart';
import '../../features/complaints/data/complaint_repository.dart';

/// One applicant a household can name as the respondent of a report.
class ReportApplicantOption {
  const ReportApplicantOption({required this.workerId, required this.label});

  final int workerId;
  final String label;
}

/// "File a Complaint" -- always tied to one job. A household picks which
/// applicant the report is about; a worker's report always targets that
/// job's household, so no picker is shown.
///
/// Returns true if a report was submitted, so the caller can show a
/// confirmation without this dialog owning any SnackBar/ScaffoldMessenger
/// context of its own.
Future<bool> showReportIssueDialog({
  required BuildContext context,
  required int jobId,
  required String jobTitle,
  required bool isHousehold,
  List<ReportApplicantOption> applicants = const [],
  ComplaintRepository repository = const ComplaintRepository(),
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _ReportIssueDialog(
      jobId: jobId,
      jobTitle: jobTitle,
      isHousehold: isHousehold,
      applicants: applicants,
      repository: repository,
    ),
  );
  return result ?? false;
}

class _ReportIssueDialog extends StatefulWidget {
  const _ReportIssueDialog({
    required this.jobId,
    required this.jobTitle,
    required this.isHousehold,
    required this.applicants,
    required this.repository,
  });

  final int jobId;
  final String jobTitle;
  final bool isHousehold;
  final List<ReportApplicantOption> applicants;
  final ComplaintRepository repository;

  @override
  State<_ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<_ReportIssueDialog> {
  String? _complaintType;
  int? _respondentId;
  final _description = TextEditingController();
  final List<String> _evidencePaths = [];
  bool _submitting = false;
  String? _error;

  static const _maxEvidence = 5;
  // The backend's image limit (apps.common.uploads.MAX_IMAGE_BYTES); checked
  // here so an oversized photo is refused now, not after a long upload.
  static const _maxEvidenceBytes = 5 * 1024 * 1024;

  Future<void> _pickEvidence() async {
    const group = XTypeGroup(
      label: 'Photo evidence',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;
    final picked = <PickedEvidence>[
      // XFile.length() also works in the web build, where dart:io File throws.
      for (final file in files)
        PickedEvidence(
          path: file.path,
          name: file.name,
          bytes: await file.length(),
        ),
    ];
    if (!mounted) return;
    final result = mergeEvidence(
      existing: _evidencePaths,
      picked: picked,
      maxCount: _maxEvidence,
      maxBytes: _maxEvidenceBytes,
    );
    setState(() {
      _evidencePaths
        ..clear()
        ..addAll(result.paths);
      _error = result.message;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_complaintType == null) {
      setState(() => _error = 'Please select a complaint type.');
      return;
    }
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what happened.');
      return;
    }
    if (widget.isHousehold && _respondentId == null) {
      setState(() => _error = 'Select which worker this complaint is about.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        jobId: widget.jobId,
        respondentId: widget.isHousehold ? _respondentId : null,
        complaintType: _complaintType!,
        description: _description.text.trim(),
        evidencePaths: _evidencePaths,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _requiredLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
          children: [
            TextSpan(text: text),
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionalLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: GawaGoColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
          children: [
            TextSpan(text: text),
            const TextSpan(
              text: ' (optional)',
              style: TextStyle(
                color: GawaGoColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Web's "File a Complaint" modal (ComplaintModal.jsx) is a plain white
    // Bootstrap modal. This dialog used to inherit whatever dark ambient
    // theme happened to be active at the call site, which clashed with the
    // rest of the app -- forcing a light theme here keeps it consistent
    // regardless of where it's opened from.
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        fontFamily: GawaGoColors.fontBody,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GawaGoColors.primary,
          brightness: Brightness.light,
        ).copyWith(primary: GawaGoColors.leafDeep),
        dialogTheme: const DialogThemeData(
          backgroundColor: GawaGoColors.surface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: GawaGoColors.input,
          hintStyle: const TextStyle(
            color: GawaGoColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GawaGoColors.border),
          ),
        ),
      ),
      child: AlertDialog(
        backgroundColor: GawaGoColors.surface,
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'File a Complaint',
                style: TextStyle(
                  color: GawaGoColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close, color: GawaGoColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'About "${widget.jobTitle}". Your complaint goes directly '
                'to our admin team for review.',
                style: const TextStyle(
                  color: GawaGoColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.isHousehold) ...[
                _requiredLabel('Who is this about?'),
                DropdownButtonFormField<int>(
                  initialValue: _respondentId,
                  decoration: const InputDecoration(
                    hintText: 'Select a worker...',
                  ),
                  items: widget.applicants
                      .map(
                        (applicant) => DropdownMenuItem(
                          value: applicant.workerId,
                          child: Text(applicant.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _respondentId = value),
                ),
                if (widget.applicants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'No workers have applied to this job yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: GawaGoColors.textMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              _requiredLabel('Complaint Type'),
              DropdownButtonFormField<String>(
                initialValue: _complaintType,
                decoration: const InputDecoration(hintText: 'Select a type...'),
                items: complaintTypeLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _complaintType = value),
              ),
              const SizedBox(height: 14),
              _requiredLabel('Description'),
              TextField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Please provide details about what happened...',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Be specific and include dates, times, and any relevant '
                'details that help us understand the issue.',
                style: TextStyle(fontSize: 11.5, color: GawaGoColors.textMuted),
              ),
              const SizedBox(height: 14),
              _optionalLabel('Photo evidence'),
              InkWell(
                onTap: _submitting ? null : _pickEvidence,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: GawaGoColors.input,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GawaGoColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.upload_outlined,
                        size: 18,
                        color: GawaGoColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _evidencePaths.isEmpty
                              ? 'Choose Files — No file chosen'
                              : 'Choose Files — ${_evidencePaths.length} '
                                    'file${_evidencePaths.length == 1 ? '' : 's'} chosen',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GawaGoColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Up to $_maxEvidence photos. Attaching a photo helps the '
                'admin see what happened.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: GawaGoColors.textMuted,
                ),
              ),
              if (_evidencePaths.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _evidencePaths
                      .map(
                        (path) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(path),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _evidencePaths.remove(path)),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(
                                    Icons.close,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GawaGoColors.leafTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: GawaGoColors.leafDeep,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        const TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            color: GawaGoColors.leafDeep,
                          ),
                          children: [
                            TextSpan(
                              text: 'Your Privacy: ',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text:
                                  'Complaints are reviewed by our admin team and '
                                  'handled confidentially. The person named '
                                  'is not notified that a complaint was '
                                  'filed.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: GawaGoColors.textMuted,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: GawaGoColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(_submitting ? 'Submitting...' : 'Submit Complaint'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One file the user picked as report evidence.
class PickedEvidence {
  const PickedEvidence({
    required this.path,
    required this.name,
    required this.bytes,
  });

  final String path;
  final String name;
  final int bytes;
}

/// Adds newly picked photos to the evidence list: files over [maxBytes] are
/// refused (the backend's image limit), duplicates are ignored, and the list
/// is capped at [maxCount]. [message] says what was left out, if anything.
({List<String> paths, String? message}) mergeEvidence({
  required List<String> existing,
  required List<PickedEvidence> picked,
  required int maxCount,
  required int maxBytes,
}) {
  final oversized = [
    for (final file in picked)
      if (file.bytes > maxBytes) file.name,
  ];
  final combined = {
    ...existing,
    for (final file in picked)
      if (file.bytes <= maxBytes) file.path,
  };
  final dropped = combined.length > maxCount;
  final megabytes = maxBytes ~/ (1024 * 1024);
  return (
    paths: combined.take(maxCount).toList(),
    message: oversized.isNotEmpty
        ? '${oversized.join(', ')}: exceeds $megabytes MB and was not added.'
        : dropped
        ? 'A complaint can carry up to $maxCount photos; only the first $maxCount were kept.'
        : null,
  );
}
