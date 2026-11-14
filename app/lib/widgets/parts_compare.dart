import 'package:flutter/material.dart';

import '../theme.dart';

/// Before / after part counts with a simple drawing: one small block per part.
/// Rows that changed are drawn in the hazard color.
class PartsCompare extends StatelessWidget {
  const PartsCompare({super.key, required this.before, required this.after});

  final Map<String, int>? before;
  final Map<String, int> after;

  static const _labelWidth = 116.0;

  static const _parts = [
    ('walls', 'Walls', Icons.view_agenda_outlined),
    ('doors', 'Doors', Icons.door_front_door_outlined),
    ('windows', 'Windows', Icons.window_outlined),
    ('openings', 'Openings', Icons.crop_free_outlined),
  ];

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: _labelWidth),
                Expanded(child: Text('Before', style: body(13, color: BB.muted))),
                Expanded(child: Text('Now', style: body(13, color: BB.muted))),
              ],
            ),
            for (final (key, label, icon) in _parts) _row(key, label, icon),
          ],
        ),
      );

  Widget _row(String key, String label, IconData icon) {
    final was = before?[key];
    final now = after[key] ?? 0;
    final changed = was != null && was != now;
    final color = changed ? BB.accent : BB.ink;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      style: body(15, color: color, weight: changed ? FontWeight.w700 : FontWeight.w500)),
                ),
              ],
            ),
          ),
          Expanded(child: _blocks(was, BB.muted)),
          Expanded(child: _blocks(now, color)),
        ],
      ),
    );
  }

  /// The number, then one block per part (at most 8 blocks).
  Widget _blocks(int? count, Color color) {
    if (count == null) return Text('no scan', style: body(14, color: BB.muted));
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 22, child: Text('$count', style: heading(17, color: color))),
        for (var i = 0; i < count && i < 8; i++)
          Container(
            width: 7,
            height: 14,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
      ],
    );
  }
}
