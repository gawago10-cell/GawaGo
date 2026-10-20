import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// List View / Map View switch. Shared so the worker's Find Jobs map and the
/// household's Matched Workers map are toggled the same way.
class ListMapViewToggle extends StatelessWidget {
  const ListMapViewToggle({
    super.key,
    required this.mapView,
    required this.onChanged,
  });

  final bool mapView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool value) {
      final active = mapView == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: Material(
            color: active ? GawaGoColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onChanged(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active
                        ? GawaGoColors.onPrimary
                        : GawaGoColors.textMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GawaGoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GawaGoColors.line),
      ),
      child: Row(
        children: [option('List View', false), option('Map View', true)],
      ),
    );
  }
}
