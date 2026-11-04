import 'package:flutter/material.dart';

import '../../core/api/gawago_api.dart';
import '../../core/errors/api_error.dart';

/// Change the signed-in account's password. There was no way to do this
/// except Forgot password, though a new admin is told to change the
/// temporary one (third scan, 2026-11-01).
Future<void> showChangePasswordDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const ChangePasswordDialog(),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Your password was updated.')));
  }
}

class ChangePasswordDialog extends StatelessWidget {
  const ChangePasswordDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SingleChildScrollView(
        child: ChangePasswordForm(
          onCancel: () => Navigator.pop(context),
          onChanged: () => Navigator.pop(context, true),
        ),
      ),
    );
  }
}

/// The password fields and buttons, used in the dialog and in the Password
/// tab of My Profile. With no [onChanged], it confirms with a snackbar and
/// clears itself.
class ChangePasswordForm extends StatefulWidget {
  const ChangePasswordForm({super.key, this.onChanged, this.onCancel});

  final VoidCallback? onChanged;
  final VoidCallback? onCancel;

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_next.text.length < 8) {
      setState(
        () => _error = 'Use at least 8 characters for the new password.',
      );
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = "The new passwords don't match.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await GawaGoApi.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      if (widget.onChanged != null) {
        widget.onChanged!();
      } else {
        _current.clear();
        _next.clear();
        _confirm.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your password was updated.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            hintText: 'At least 8 characters',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null) ...[
              TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Updating…' : 'Update Password'),
            ),
          ],
        ),
      ],
    );
  }
}
