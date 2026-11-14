import 'package:flutter/material.dart';

import '../theme.dart';

/// What a pill means. Every kind has its own color AND icon (color-blind safe).
enum PillKind { safe, help, noAnswer, danger, hazard, exit, neutral }

/// A small rounded label with an icon and a word.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.kind = PillKind.neutral, this.icon});

  final String label;
  final PillKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, defaultIcon) = switch (kind) {
      PillKind.safe => (BB.safeSoft, BB.safe, Icons.check_circle_outline),
      PillKind.help => (BB.help, BB.helpText, Icons.pan_tool_outlined),
      PillKind.noAnswer => (BB.noAnswer, BB.white, Icons.help_outline),
      PillKind.danger => (BB.danger, BB.white, Icons.warning_amber_outlined),
      PillKind.hazard => (BB.hazardSoft, BB.accent, Icons.report_problem_outlined),
      PillKind.exit => (BB.exitSoft, BB.exit, Icons.stairs_outlined),
      PillKind.neutral => (BB.line, BB.muted, Icons.circle_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? defaultIcon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(label, style: body(13, color: foreground, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
