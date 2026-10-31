import 'package:flutter/material.dart';

/// Why the worker can't apply right now, in the backend's own words (on a
/// full-time job until that household marks it done, or already hired on
/// these days) -- the mobile twin of the web's .job-blocked-note.
class ApplyBlockedNote extends StatelessWidget {
  const ApplyBlockedNote({super.key, required this.reason, this.lead = ''});

  final String reason;

  /// The backend's short lead; a generic one when it sent none.
  final String lead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8D49A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.pause_circle_outline,
              size: 18,
              color: Color(0xFF6A5317),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${lead.isEmpty ? "You can't apply right now." : lead} ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: reason),
                ],
              ),
              style: const TextStyle(
                color: Color(0xFF6A5317),
                fontSize: 13.5,
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

/// The Apply button's wording: "Not available" while a full-time job blocks
/// the worker, "Applied" once they have applied.
String applyButtonLabel({required bool canApply, required String blocked}) {
  if (canApply) return 'Apply Now';
  return blocked.isNotEmpty ? 'Not available' : 'Applied';
}
