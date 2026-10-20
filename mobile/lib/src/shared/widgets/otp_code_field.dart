import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/gawago_colors.dart';

/// A segmented one-box-per-digit code input (the GCash/OTP style), sized to
/// [length] automatically -- a 6-digit code gets 6 boxes. Mirrors the web
/// app's OtpCodeInput so the reset-code step looks and behaves the same on
/// both platforms.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.length,
    required this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late final List<TextEditingController> _controllers = List.generate(
    widget.length,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    widget.length,
    (_) => FocusNode(),
  );

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _emit() {
    final value = _value;
    widget.onChanged(value);
    // Joining one char per box only reaches widget.length when every box
    // actually has a digit -- a missing one joins to nothing, shortening
    // the string, so length alone is a complete check.
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _handleChanged(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _controllers[index].text = '';
      _emit();
      return;
    }
    // Paste or autofill can drop more than one digit into a single box --
    // spread the rest across the following ones instead of truncating.
    var cursor = index;
    for (final char in digits.split('')) {
      if (cursor >= widget.length) break;
      _controllers[cursor].text = char;
      cursor += 1;
    }
    _emit();
    final focusIndex = (cursor < widget.length) ? cursor : widget.length - 1;
    _focusNodes[focusIndex].requestFocus();
    _controllers[focusIndex].selection = TextSelection.fromPosition(
      TextPosition(offset: _controllers[focusIndex].text.length),
    );
  }

  void _handleBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].text = '';
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _OtpBox(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            enabled: widget.enabled,
            autofocus: widget.autofocus && i == 0,
            onChanged: (raw) => _handleChanged(i, raw),
            onBackspace: () => _handleBackspace(i),
          ),
        ],
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.autofocus,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      // Focus (not KeyboardListener) so backspace-on-empty is caught without
      // a second FocusNode competing with the TextField's own for focus.
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // No maxLength here on purpose: Flutter truncates to it before
          // onChanged ever fires, which would silently drop every digit
          // past the first from a paste or SMS autofill. _handleChanged
          // below is what actually keeps each box to one character.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: GawaGoColors.deepGreen.withValues(alpha: 0.6),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: GawaGoColors.borderGreen.withValues(alpha: 0.6),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: GawaGoColors.borderGreen.withValues(alpha: 0.6),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: GawaGoColors.primary,
                width: 2,
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
