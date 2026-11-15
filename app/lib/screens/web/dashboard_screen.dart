import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../models/snapshot.dart';
import '../../theme.dart';
import '../../util.dart';
import '../../widgets/athena_dock.dart';
import '../../widgets/floor_map.dart';
import '../../widgets/floor_tabs.dart';
import '../../widgets/hold_button.dart';
import '../../widgets/live_builder.dart';
import '../../widgets/logo.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_pill.dart';

/// Web dashboard for the supervisor: 3D model, 2D map with worker dots, hazards, crew.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int? _floor; // the selected floor tab
  bool _busy = false;

  Future<void> _call(Live live, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await live.refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
    builder: (context, live) {
      final snapshot = live.snapshot;
      return Scaffold(
        body: SafeArea(
          child: AthenaDock(
            api: live.api,
            role: 'supervisor',
            child: snapshot == null
              ? Center(
                  child: Text(
                    live.offline
                        ? 'No connection to the server yet.\n${live.api.baseUrl}'
                        : 'Connecting to the server...\n${live.api.baseUrl}',
                    textAlign: TextAlign.center,
                    style: body(16, color: BB.muted),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) => ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: box.maxWidth > 700 ? 28 : 16,
                      vertical: 16,
                    ),
                    children: _content(
                      live,
                      snapshot,
                      wide: box.maxWidth > 980,
                    ),
                  ),
                ),
          ),
        ),
      );
    },
  );

  List<Widget> _content(Live live, Snapshot snapshot, {required bool wide}) {
    final floors = knownFloors(
      snapshot.scans.keys,
      snapshot.workers.map((w) => w.floor),
    );
    final floor = floors.contains(_floor)
        ? _floor
        : (floors.isEmpty ? null : floors.first);
    final crew = snapshot.workers.where((w) => w.floor == floor).toList();
    final openHazards = snapshot.hazards.where((h) => h.open).toList()
      ..sort(
        (a, b) =>
            (a.floor == floor ? 0 : 1).compareTo(b.floor == floor ? 0 : 1),
      );
    final scannedToday = snapshot.scans.values
        .where((s) => isToday(s.ts))
        .length;

    final mapColumn = [
      if (floor != null) ...[
        _card('3D scan of Floor $floor', _model(live, snapshot.scans[floor])),
        const SizedBox(height: 16),
        _card(
          'Floor $floor map',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FloorMap(
                floor: floor,
                workers: crew,
                rescue: snapshot.rescueActive,
              ),
              const SizedBox(height: 10),
              Text(
                'Location only, no camera. Dots show the zone, not the exact spot.',
                style: body(13, color: BB.muted),
              ),
            ],
          ),
        ),
      ],
    ];
    final listColumn = [
      _card('Open hazards', _hazards(live, openHazards)),
      const SizedBox(height: 16),
      _card(
        floor == null ? 'Crew' : 'Crew on Floor $floor (${crew.length})',
        _crew(crew),
      ),
    ];

    return [
      _topBar(live, snapshot),
      const SizedBox(height: 16),
      if (live.offline) ...[const OfflineBanner(), const SizedBox(height: 16)],
      if (snapshot.rescueActive) ...[
        _rescueBanner(snapshot),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Expanded(child: _tile('${snapshot.workers.length}', 'On site')),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              '${openHazards.length}',
              'Open hazards',
              color: openHazards.isEmpty ? BB.ink : BB.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              '$scannedToday/${floors.length}',
              'Floors scanned today',
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FloorTabs(
        floors: floors,
        selected: floor,
        onSelect: (f) => setState(() => _floor = f),
        badge: (f) => '${snapshot.workers.where((w) => w.floor == f).length}',
      ),
      const SizedBox(height: 16),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: Column(children: mapColumn)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Column(children: listColumn)),
          ],
        )
      else ...[
        ...mapColumn,
        const SizedBox(height: 16),
        ...listColumn,
      ],
    ];
  }

  Widget _topBar(Live live, Snapshot snapshot) => Wrap(
    spacing: 16,
    runSpacing: 12,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Logo(size: 40),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycl0ps', semanticsLabel: 'Cyclops',
                  style: body(13, color: BB.muted, weight: FontWeight.w600),
                ),
                Text(snapshot.siteName, style: heading(24)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (snapshot.rescueActive)
            const StatusPill('Rescue Mode', kind: PillKind.danger)
          else if (live.connected)
            const StatusPill('Live', kind: PillKind.safe, icon: Icons.sensors)
          else
            const StatusPill(
              'No connection',
              kind: PillKind.hazard,
              icon: Icons.wifi_off,
            ),
        ],
      ),
      if (!snapshot.rescueActive)
        SizedBox(
          width: 300,
          child: HoldButton(
            label: 'Start Rescue Mode',
            busy: _busy,
            onHeld: () =>
                _call(live, () => live.api.rescueStart('supervisor button')),
          ),
        ),
    ],
  );

  Widget _rescueBanner(Snapshot snapshot) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: BB.danger,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_outlined, color: BB.white, size: 32),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Rescue Mode is on'
                '${snapshot.rescueStartedAt == null ? '' : ' since ${clockText(snapshot.rescueStartedAt!)}'}'
                '${snapshot.rescueReason == null ? '' : '. Reason: ${snapshot.rescueReason}'}',
                style: heading(18, color: BB.white),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => context.go('/rescue'),
            icon: const Icon(Icons.open_in_new),
            label: Text('Open rescuer page', style: heading(16, color: BB.ink)),
            style: FilledButton.styleFrom(
              backgroundColor: BB.white,
              foregroundColor: BB.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _model(Live live, ScanInfo? scan) {
    final model = scan?.model;
    if (model == null || !model.endsWith('.glb')) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'No 3D model for this floor yet.',
            style: body(15, color: BB.muted),
          ),
        ),
      );
    }
    final parts = scan!.parts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 340,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ModelViewer(
              key: ValueKey(model), // a new scan loads a new model
              src: '${live.api.baseUrl}/files/$model',
              alt: '3D scan of the floor',
              backgroundColor: BB.ground,
              cameraControls: true,
              autoRotate: true,
              cameraOrbit: '30deg 55deg auto',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${isToday(scan.ts) ? 'Scanned today at ${clockText(scan.ts)}' : 'Last scan: ${agoText(scan.ts)}'}. '
          '${parts['walls'] ?? 0} walls, ${parts['doors'] ?? 0} doors, '
          '${parts['windows'] ?? 0} windows, ${parts['openings'] ?? 0} openings.',
          style: body(13, color: BB.muted),
        ),
      ],
    );
  }

  Widget _hazards(Live live, List<Hazard> hazards) {
    if (hazards.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.check_circle_outline, color: BB.safe),
          const SizedBox(width: 10),
          Text('No open hazards', style: body(16, weight: FontWeight.w600)),
        ],
      );
    }
    return Column(
      children: [
        for (final hazard in hazards)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
            child: Row(
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  color: BB.accent,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hazard.text,
                        style: body(15, weight: FontWeight.w700),
                      ),
                      Text(
                        'Floor ${hazard.floor}. ${hazard.oshaTopic}',
                        style: body(13, color: BB.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _call(
                            live,
                            () => live.api.setHazardStatus(hazard.id, 'fixed'),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: BB.safe,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Mark fixed',
                      style: body(14, color: BB.white, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _crew(List<WorkerInfo> crew) {
    if (crew.isEmpty) {
      return Text('Nobody on this floor.', style: body(15, color: BB.muted));
    }
    return Column(
      children: [
        for (final worker in crew)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: BB.ink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    worker.zone ?? '?',
                    style: heading(15, color: BB.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.name,
                        style: body(15, weight: FontWeight.w600),
                      ),
                      Text(
                        'Last ping ${agoText(worker.lastPing)}'
                        '${worker.battery == null ? '' : ', battery ${worker.battery}%'}'
                        '${worker.source == 'mesh' ? ', via mesh' : ''}',
                        style: body(12, color: BB.muted),
                      ),
                    ],
                  ),
                ),
                if (worker.status == 'help')
                  const StatusPill('Needs help', kind: PillKind.help)
                else if (worker.status == 'safe')
                  const StatusPill('Safe', kind: PillKind.safe)
                else if (worker.phoneLost)
                  const StatusPill('Phone lost', kind: PillKind.noAnswer)
                else if (!worker.moving)
                  const StatusPill('Not moving', icon: Icons.pause_circle_outline),
              ],
            ),
          ),
      ],
    );
  }

  Widget _card(String title, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: heading(18)),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _tile(String value, String label, {Color color = BB.ink}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          child: Text(value, style: heading(34, color: color)),
        ),
        Text(label, style: body(13, color: BB.muted)),
      ],
    ),
  );
}
