import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

class PersistentActionBar extends StatelessWidget {
  const PersistentActionBar({
    super.key,
    required this.children,
    this.busy = false,
  });

  final List<Widget> children;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty && !busy) return const SizedBox.shrink();
    return Material(
      elevation: 10,
      color: GawaGoColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (busy && children.isNotEmpty) const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
