import 'package:flutter/material.dart';

/// Asks for a reason the other person will read (a certificate rejection,
/// a cancelled job). The action stays off until something is typed, and the
/// trimmed text comes back; null means the dialog was cancelled.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String message = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      label: label,
      actionLabel: actionLabel,
      message: message,
    ),
  );
}

// Its own widget so the text controller lives exactly as long as the
// dialog, including its closing animation.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
    required this.message,
  });

  final String title;
  final String label;
  final String actionLabel;
  final String message;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.isNotEmpty) ...[
            Text(widget.message),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _reason,
            maxLines: 3,
            maxLength: 300,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.label),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.pop(context, reason),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
