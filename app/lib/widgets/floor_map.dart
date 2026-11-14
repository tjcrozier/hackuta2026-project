import 'dart:math';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/snapshot.dart';
import '../theme.dart';
import '../util.dart';

/// Where to draw `count` dots around a zone center so they do not overlap.
/// The first dot is at the center; the rest go around it in a spiral.
List<Offset> spreadDots(int count, Offset center, double step) => [
      for (var i = 0; i < count; i++)
        center + Offset.fromDirection(i * 2.399963, step * sqrt(i)), // 2.4 rad = golden angle
    ];

/// 2D floor map with one dot per worker. Dots sit at the zone center, not the exact spot.
/// With `rescue` on, dots use the status colors and "no answer" dots pulse.
class FloorMap extends StatelessWidget {
  const FloorMap({super.key, required this.floor, required this.workers, this.rescue = false});

  final int floor;
  final List<WorkerInfo> workers; // only the workers on this floor
  final bool rescue;

  static const _dot = 30.0;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.7,
        child: LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          Offset at((double, double) spot) => Offset(spot.$1 * size.width, spot.$2 * size.height);
          final centers = Config.floorZoneCenters[floor] ?? Config.zoneCenters;

          // Group the workers by zone, then spread each group around its center.
          final groups = <String?, List<WorkerInfo>>{};
          for (final worker in workers) {
            groups.putIfAbsent(centers.containsKey(worker.zone) ? worker.zone : null, () => [])
                .add(worker);
          }
          final dots = <Widget>[];
          groups.forEach((zone, group) {
            final center = at(zone == null ? Config.unknownZoneCenter : centers[zone]!);
            final spots = spreadDots(group.length, center, _dot * 1.08);
            for (var i = 0; i < group.length; i++) {
              dots.add(Positioned(
                left: spots[i].dx - _dot / 2,
                top: spots[i].dy - _dot / 2,
                child: _WorkerDot(worker: group[i], rescue: rescue, size: _dot),
              ));
            }
          });

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _FloorPainter(centers.length))),
              // Zone letters
              for (final entry in centers.entries)
                Positioned(
                  left: at(entry.value).dx - 40,
                  top: 10,
                  width: 80,
                  child: Text('ZONE ${entry.key}',
                      textAlign: TextAlign.center,
                      style: heading(13, color: BB.muted, weight: FontWeight.w600)),
                ),
              if (groups.containsKey(null))
                Positioned(
                  left: at(Config.unknownZoneCenter).dx - 40,
                  top: at(Config.unknownZoneCenter).dy + _dot,
                  width: 80,
                  child: Text('Zone unknown',
                      textAlign: TextAlign.center, style: body(11, color: BB.muted)),
                ),
              // Stairs (exits are always blue)
              for (final entry in Config.stairs.entries)
                Positioned(
                  left: at(entry.value).dx - 44,
                  top: at(entry.value).dy - 13,
                  width: 88,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                      color: BB.exitSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BB.exit),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.stairs_outlined, size: 15, color: BB.exit),
                        const SizedBox(width: 4),
                        Text(entry.key, style: body(12, color: BB.exit, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ...dots,
            ],
          );
        }),
      );
}

/// The floor outline and the lines between zones.
class _FloorPainter extends CustomPainter {
  _FloorPainter(this.zones);
  final int zones;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(outline, Paint()..color = BB.white);
    final divider = Paint()
      ..color = BB.line
      ..strokeWidth = 2;
    for (var i = 1; i < zones; i++) {
      final x = size.width * i / zones;
      canvas.drawLine(Offset(x, 34), Offset(x, size.height - 12), divider);
    }
    canvas.drawRRect(
      outline,
      Paint()
        ..color = BB.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_FloorPainter old) => old.zones != zones;
}

/// One worker on the map. Color AND icon show the status (color-blind safe).
class _WorkerDot extends StatelessWidget {
  const _WorkerDot({required this.worker, required this.rescue, required this.size});

  final WorkerInfo worker;
  final bool rescue;
  final double size;

  String get _initials {
    final words = worker.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    Color background = BB.ink;
    Color foreground = BB.white;
    IconData? icon;
    var statusText = 'On site';
    if (worker.status == 'help') {
      (background, foreground, icon, statusText) =
          (BB.help, BB.helpText, Icons.pan_tool_outlined, 'Needs help');
    } else if (rescue && worker.status == 'safe') {
      (background, icon, statusText) = (BB.safe, Icons.check, 'Safe');
    } else if (rescue) {
      (background, icon, statusText) = (BB.noAnswer, Icons.question_mark, 'No answer');
    } else if (worker.phoneLost) {
      (background, icon, statusText) = (BB.noAnswer, Icons.phonelink_erase_outlined, 'Phone lost');
    }

    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: BB.white, width: 2),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: foreground)
          : Text(_initials, style: body(size * 0.36, color: foreground, weight: FontWeight.w700)),
    );
    final pulsing = rescue && worker.status == 'none';
    return Tooltip(
      message: '${worker.name}\n$statusText. Zone ${worker.zone ?? 'unknown'}. '
          'Last ping ${agoText(worker.lastPing)}'
          '${worker.source == 'mesh' ? ' (via mesh)' : ''}',
      child: pulsing ? _Pulse(size: size, child: dot) : dot,
    );
  }
}

/// A halo that grows and fades behind a "no answer" dot.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _beat =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _beat,
        child: widget.child,
        builder: (context, child) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // OverflowBox lets the halo be bigger than the dot without moving it.
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: OverflowBox(
                maxWidth: widget.size * 2.4,
                maxHeight: widget.size * 2.4,
                child: Container(
                  width: widget.size * (1 + 1.4 * _beat.value),
                  height: widget.size * (1 + 1.4 * _beat.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BB.danger.withValues(alpha: 0.45 * (1 - _beat.value)),
                  ),
                ),
              ),
            ),
            child!,
          ],
        ),
      );
}
