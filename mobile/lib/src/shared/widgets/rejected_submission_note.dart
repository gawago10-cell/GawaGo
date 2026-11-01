import 'package:flutter/material.dart';

/// Above the resubmit form: the last submission was rejected, and why, so
/// the person knows what to fix (third scan, 2026-11-01). The mobile twin of
/// the web's .verification-rejected-note.
class RejectedSubmissionNote extends StatelessWidget {
  const RejectedSubmissionNote({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3DF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFECD2A2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline,
              size: 18,
              color: Color(0xFF7A5216),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Your last submission was rejected. ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (reason.isNotEmpty) TextSpan(text: 'Reason: “$reason” '),
                  const TextSpan(
                    text: 'Fix this and submit again; an admin will review it.',
                  ),
                ],
              ),
              style: const TextStyle(
                color: Color(0xFF7A5216),
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
