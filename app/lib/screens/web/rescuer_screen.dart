import 'package:flutter/material.dart';

import '../../models/snapshot.dart';
import '../../theme.dart';
import '../../util.dart';
import '../../widgets/floor_map.dart';
import '../../widgets/floor_tabs.dart';
import '../../widgets/live_builder.dart';
import '../../widgets/status_pill.dart';
import '../supervisor_home.dart' show exitFor;

/// The rescuer link: one page, no app, no login, view-only.
/// Shows who is missing, where they were last seen, and the nearest stairs.
class RescuerScreen extends StatefulWidget {
  const RescuerScreen({super.key});

  /// Who to find first: no answer before help, highest floor first. Safe people are left out.
  static List<WorkerInfo> toFind(List<WorkerInfo> workers) =>
      workers.where((w) => w.status != 'safe').toList()
        ..sort((a, b) {
          final byStatus = (a.status == 'none' ? 0 : 1).compareTo(b.status == 'none' ? 0 : 1);
          if (byStatus != 0) return byStatus;
          return (b.floor ?? -999).compareTo(a.floor ?? -999);
        });

  @override
  State<RescuerScreen> createState() => _RescuerScreenState();
}

class _RescuerScreenState extends State<RescuerScreen> {
  int? _floor;

  @override
  Widget build(BuildContext context) => LiveBuilder(builder: (context, live) {
        final snapshot = live.snapshot;
        return Scaffold(
          body: snapshot == null
              ? Center(
                  child: Text(
                      live.offline
                          ? 'No connection to the server yet. Retrying by itself.'
                          : 'Connecting to the server...',
                      style: body(16, color: BB.muted)),
                )
              : Column(
                  children: [
                    _header(snapshot, live.connected),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => ListView(
                          padding: EdgeInsets.symmetric(
                              horizontal: box.maxWidth > 700 ? 28 : 16, vertical: 16),
                          children: _content(snapshot, wide: box.maxWidth > 980),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      });

  Widget _header(Snapshot snapshot, bool connected) {
    final active = snapshot.rescueActive;
    return Container(
      width: double.infinity,
      color: active ? BB.danger : BB.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              Icon(active ? Icons.warning_amber_outlined : Icons.shield_outlined,
                  color: BB.white, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(active ? 'Rescue Mode' : 'No emergency right now',
                        style: heading(26, color: BB.white)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        snapshot.siteName,
                        if (active && snapshot.rescueStartedAt != null)
                          'Started ${clockText(snapshot.rescueStartedAt!)} '
                              '(${elapsedText(snapshot.rescueStartedAt)} ago)',
                        if (active && snapshot.rescueReason != null) snapshot.rescueReason!,
                        if (!connected) 'No connection, showing the last data',
                      ].join('  |  '),
                      style: body(14, color: BB.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(Snapshot snapshot, {required bool wide}) {
    final rescue = snapshot.rescueActive;
    final workers = snapshot.workers;
    int count(String status) => workers.where((w) => w.status == status).length;
    int missingOn(int floor) =>
        workers.where((w) => w.floor == floor && w.status == 'none').length;

    final floors = knownFloors(snapshot.scans.keys, workers.map((w) => w.floor));
    // Open on the floor with the most missing people.
    final worstFloor = floors.isEmpty
        ? null
        : floors.reduce((a, b) => missingOn(b) > missingOn(a) ? b : a);
    final floor = floors.contains(_floor) ? _floor : worstFloor;
    final toFind = RescuerScreen.toFind(workers);
    final safe = workers.where((w) => w.status == 'safe').toList();

    final mapColumn = [
      FloorTabs(
        floors: floors,
        selected: floor,
        onSelect: (f) => setState(() => _floor = f),
        badge: rescue ? (f) => missingOn(f) == 0 ? null : '${missingOn(f)} missing' : null,
        badgeColor: BB.noAnswer,
      ),
      const SizedBox(height: 12),
      if (floor != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Floor $floor, last known zones', style: heading(18)),
              const SizedBox(height: 12),
              FloorMap(
                floor: floor,
                workers: workers.where((w) => w.floor == floor).toList(),
                rescue: rescue,
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill('No answer', kind: PillKind.noAnswer),
                  StatusPill('Needs help', kind: PillKind.help),
                  StatusPill('Safe', kind: PillKind.safe),
                  StatusPill('Stairs', kind: PillKind.exit),
                ],
              ),
              const SizedBox(height: 8),
              Text('Dots show the zone where the phone was last seen, not the exact spot.',
                  style: body(13, color: BB.muted)),
            ],
          ),
        ),
    ];

    final listColumn = [
      Text(rescue ? 'People to find first' : 'People on site', style: heading(20)),
      const SizedBox(height: 10),
      if (toFind.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(color: BB.safeSoft, border: BB.safe),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: BB.safe, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Everyone is marked safe.', style: heading(18, color: BB.safe)),
              ),
            ],
          ),
        ),
      for (final worker in toFind) _person(worker, rescue),
      if (safe.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Safe (${safe.length})', style: heading(16, color: BB.safe)),
        const SizedBox(height: 6),
        Text(safe.map((w) => w.name).join(', '), style: body(15, color: BB.muted)),
      ],
    ];

    return [
      Row(
        children: [
          Expanded(
            child: _count('${rescue ? count('none') : 0}', 'No answer', Icons.question_mark,
                BB.noAnswer, BB.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _count('${count('help')}', 'Need help', Icons.pan_tool_outlined, BB.help,
                BB.helpText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _count('${count('safe')}', 'Safe', Icons.check_circle_outline, BB.safeSoft,
                BB.safe),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: mapColumn),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: listColumn),
            ),
          ],
        )
      else ...[...mapColumn, const SizedBox(height: 20), ...listColumn],
    ];
  }

  Widget _count(String value, String label, IconData icon, Color background, Color foreground) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: heading(38, color: foreground)),
                  Text(label, style: body(14, color: foreground, weight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _person(WorkerInfo worker, bool rescue) {
    final pill = worker.status == 'help'
        ? const StatusPill('Needs help', kind: PillKind.help)
        : rescue
            ? const StatusPill('No answer', kind: PillKind.noAnswer)
            : const StatusPill('On site');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(worker.name, style: heading(19))),
              pill,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            worker.floor == null
                ? 'Last seen: unknown'
                : 'Last seen: Floor ${worker.floor}, Zone ${worker.zone ?? 'unknown'}',
            style: body(16, weight: FontWeight.w700),
          ),
          Text(
            'Last ping ${agoText(worker.lastPing)}'
            '${worker.battery == null ? '' : '  |  battery ${worker.battery}%'}'
            '${worker.moving ? '' : '  |  not moving'}',
            style: body(13, color: BB.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(exitFor(worker.zone), kind: PillKind.exit),
              if (worker.source == 'mesh')
                const StatusPill('via mesh', icon: Icons.hub_outlined),
            ],
          ),
        ],
      ),
    );
  }
}
