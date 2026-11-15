import 'package:flutter/material.dart';

import '../theme.dart';

/// A row of big floor buttons. `badge` is a small number shown on a floor (or null).
class FloorTabs extends StatelessWidget {
  const FloorTabs({
    super.key,
    required this.floors,
    required this.selected,
    required this.onSelect,
    this.badge,
    this.badgeColor = BB.ink,
  });

  final List<int> floors;
  final int? selected;
  final ValueChanged<int> onSelect;
  final String? Function(int floor)? badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final floor in floors)
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => onSelect(floor),
            style: FilledButton.styleFrom(
              backgroundColor: floor == selected ? BB.ink : BB.white,
              foregroundColor: floor == selected ? BB.white : BB.ink,
              side: const BorderSide(color: BB.ink, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Floor $floor',
                  style: heading(
                    17,
                    color: floor == selected ? BB.white : BB.ink,
                  ),
                ),
                if (badge?.call(floor) != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: floor == selected ? BB.white : BB.ink,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!(floor)!,
                      style: body(
                        13,
                        color: floor == selected ? BB.ink : BB.white,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}

/// Every floor that has a scan or a worker, top floor first.
List<int> knownFloors(Iterable<int> scanFloors, Iterable<int?> workerFloors) =>
    <int>{...scanFloors, ...workerFloors.whereType<int>()}.toList()
      ..sort((a, b) => b.compareTo(a));
