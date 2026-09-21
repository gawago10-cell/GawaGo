import 'package:flutter/material.dart';

import '../utils/display_formatters.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.prefix, this.label});

  final String status;
  final String? prefix;

  /// Overrides the auto-formatted status text (e.g. for application
  /// statuses, which use Applied/Hired/Rejected rather than a
  /// title-cased raw status). Falls back to [formatStatus] when omitted.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final displayText = label ?? formatStatus(status);
    final resolvedLabel = prefix == null
        ? displayText
        : '$prefix: $displayText';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        resolvedLabel,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.status,
    this.trailing,
    this.onTap,
    this.emphasized = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? status;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final hasTrailing = trailing != null || onTap != null;
    final actionPadding = trailing != null ? 74.0 : 34.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: emphasized ? color.withValues(alpha: 0.09) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: emphasized
              ? color.withValues(alpha: 0.55)
              : const Color(0xFFD8D0C3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  right: hasTrailing ? actionPadding : 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: color.withValues(alpha: 0.14),
                      foregroundColor: color,
                      child: Icon(icon, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF10251A),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          if (status != null && status!.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(status: status!),
                            ),
                          ],
                          const SizedBox(height: 7),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFF355444),
                              fontSize: 13,
                              height: 1.3,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Positioned(top: 0, right: 0, child: trailing!)
              else if (onTap != null)
                const Positioned(
                  top: 7,
                  right: 0,
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color statusColor(String? status) {
  return switch (status?.trim().toLowerCase()) {
    'verified' || 'completed' || 'hired' || 'accepted' => Colors.green,
    'pending' || 'hire_requested' || 'completion_requested' => Colors.orange,
    'rejected' || 'cancelled' => Colors.red,
    'assigned' || 'open' => Colors.blue,
    _ => Colors.blueGrey,
  };
}
