import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/snapshot.dart';
import '../services/api.dart';
import '../services/live_socket.dart';
import '../services/shift.dart';
import '../services/snapshot_cache.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/athena_chat.dart' show athenaIcon;
import '../widgets/big_button.dart';
import '../widgets/hold_button.dart';
import '../widgets/logo.dart';
import '../widgets/offline_banner.dart';
import '../widgets/status_pill.dart';
import 'supervisor_rescue.dart';

/// Supervisor home: today's scans, open hazards, crew per floor, and the red hold button.
/// While Rescue Mode is on it shows the rescue summary instead.
class SupervisorHome extends StatefulWidget {
  const SupervisorHome({super.key});

  @override
  State<SupervisorHome> createState() => _SupervisorHomeState();
}

class _SupervisorHomeState extends State<SupervisorHome> {
  late final Api _api = context.read<Shift>().api;
  LiveSocket? _socket;
  Timer? _clock; // redraws "x s ago" texts
  Snapshot? _snapshot;
  bool _connected = false;
  bool _busy = false;
  final _openedAt = DateTime.now();

  /// No connection for a few seconds (so the banner does not flash on every load).
  bool get _offline => !_connected && DateTime.now().difference(_openedAt).inSeconds >= 4;

  @override
  void initState() {
    super.initState();
    _socket = LiveSocket(
      baseUrl: _api.baseUrl,
      onSnapshot: (snapshot) {
        if (mounted) setState(() => _snapshot = snapshot);
      },
      onConnected: (connected) {
        if (mounted) setState(() => _connected = connected);
      },
    )..connect();
    SnapshotCache.load().then((saved) {
      if (mounted && _snapshot == null && saved != null) {
        setState(() => _snapshot = saved);
      }
    });
    _refresh();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _socket?.close();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await _api.state();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {}
  }

  /// Runs a server call and shows a message if it fails.
  Future<void> _call(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRescue() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop Rescue Mode?', style: heading(20)),
        content: Text(
          'Only stop when everyone is accounted for. Worker phones go back to normal.',
          style: body(15),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          BigButton(
            label: 'Yes, stop Rescue Mode',
            color: BB.ink,
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'Keep it on',
            outlined: true,
            height: 56,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (sure == true) await _call(_api.rescueStop);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot != null && snapshot.rescueActive) {
      return SupervisorRescue(
        snapshot: snapshot,
        busy: _busy,
        onStop: _stopRescue,
      );
    }
    return Scaffold(
      appBar: AppBar(
        // Long-press the logo for the hidden demo tools.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Logo(size: 32),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                snapshot?.siteName.isNotEmpty == true ? snapshot!.siteName : 'Supervisor',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _connected
                  ? const StatusPill(
                      'Live',
                      kind: PillKind.safe,
                      icon: Icons.sensors,
                    )
                  : const StatusPill(
                      'No connection',
                      kind: PillKind.hazard,
                      icon: Icons.wifi_off,
                    ),
            ),
          ),
        ],
      ),
      body: snapshot == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _offline
                      ? 'No connection to the server yet, and nothing saved on this phone.\n'
                          'Check the Server address on the first screen.\n${_api.baseUrl}'
                      : 'Connecting to the server...\n${_api.baseUrl}',
                  textAlign: TextAlign.center,
                  style: body(16, color: BB.muted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: _content(snapshot),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: HoldButton(
            label: 'Start Rescue Mode',
            busy: _busy,
            onHeld: () => _call(() => _api.rescueStart('supervisor button')),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(Snapshot snapshot) {
    final openHazards = snapshot.hazards.where((h) => h.open).toList();
    // Every floor we know about, top floor first.
    final floors = <int>{
      ...snapshot.scans.keys,
      ...snapshot.workers.map((w) => w.floor).whereType<int>(),
    }.toList()..sort((a, b) => b.compareTo(a));
    final scannedToday = snapshot.scans.values
        .where((s) => isToday(s.ts))
        .length;

    return [
      if (_offline) ...[
        const OfflineBanner(message: 'The red button needs the server.'),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(child: _tile('${snapshot.workers.length}', 'On site')),
          const SizedBox(width: 10),
          Expanded(
            child: _tile(
              '${openHazards.length}',
              'Open hazards',
              color: openHazards.isEmpty ? BB.ink : BB.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tile('$scannedToday/${floors.length}', 'Scanned today'),
          ),
        ],
      ),
      if (Config.featureAthena) ...[
        const SizedBox(height: 12),
        BigButton(
          label: 'Ask Athena',
          icon: athenaIcon,
          outlined: true,
          height: 56,
          onPressed: () => context.push('/athena?role=supervisor'),
        ),
      ],
      _sectionTitle('Open hazards'),
      if (openHazards.isEmpty)
        _plainCard(
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: BB.safe),
              const SizedBox(width: 10),
              Text('No open hazards', style: body(16, weight: FontWeight.w600)),
            ],
          ),
        ),
      for (final hazard in openHazards)
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/hazard/${hazard.id}'),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  color: BB.accent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hazard.text,
                        style: body(16, weight: FontWeight.w700),
                      ),
                      Text(
                        'Floor ${hazard.floor}. ${hazard.oshaTopic}',
                        style: body(13, color: BB.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: BB.accent),
              ],
            ),
          ),
        ),
      _sectionTitle('Today\'s scans'),
      for (final floor in floors) _scanRow(floor, snapshot.scans[floor]),
      _sectionTitle('Crew'),
      for (final floor in floors)
        _crewCard(
          floor,
          snapshot.workers.where((w) => w.floor == floor).toList(),
        ),
      if (snapshot.workers.any((w) => w.floor == null))
        _crewCard(
          null,
          snapshot.workers.where((w) => w.floor == null).toList(),
        ),
    ];
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: heading(18)),
  );

  Widget _plainCard(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: cardBox(),
    child: child,
  );

  Widget _tile(String value, String label, {Color color = BB.ink}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          child: Text(value, style: heading(30, color: color)),
        ),
        const SizedBox(height: 2),
        Text(label, style: body(13, color: BB.muted)),
      ],
    ),
  );

  Widget _scanRow(int floor, ScanInfo? scan) {
    final today = scan != null && isToday(scan.ts);
    final parts = scan?.parts ?? const {};
    return _plainCard(
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Floor $floor', style: heading(18)),
                    today
                        ? StatusPill(
                            'Scanned ${clockText(scan.ts)}',
                            kind: PillKind.safe,
                          )
                        : const StatusPill(
                            'Not scanned today',
                            kind: PillKind.hazard,
                            icon: Icons.schedule_outlined,
                          ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  scan == null
                      ? 'No scan yet'
                      : '${parts['walls'] ?? 0} walls, ${parts['doors'] ?? 0} doors, '
                            '${parts['windows'] ?? 0} windows, ${parts['openings'] ?? 0} openings',
                  style: body(14, color: BB.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => context.push('/scan?floor=$floor'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BB.ink,
                side: const BorderSide(color: BB.ink, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Scan', style: body(15, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crewCard(int? floor, List<WorkerInfo> crew) => _plainCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              floor == null ? 'Floor unknown' : 'Floor $floor',
              style: heading(18),
            ),
            const Spacer(),
            Text(
              '${crew.length} ${crew.length == 1 ? 'person' : 'people'}',
              style: body(14, color: BB.muted),
            ),
          ],
        ),
        for (final worker in crew)
          Padding(
            padding: const EdgeInsets.only(top: 8),
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
                  child: Text(
                    worker.name,
                    style: body(16, weight: FontWeight.w600),
                  ),
                ),
                if (worker.status == 'help')
                  const StatusPill('Needs help', kind: PillKind.help)
                else if (worker.phoneLost)
                  const StatusPill('Phone lost', kind: PillKind.noAnswer)
                else
                  Text(
                    agoText(worker.lastPing),
                    style: body(13, color: BB.muted),
                  ),
              ],
            ),
          ),
        if (crew.isEmpty) Text('Nobody here', style: body(14, color: BB.muted)),
      ],
    ),
  );
}

/// Zone exits are shown in the rescue list too.
String exitFor(String? zone) => Config.zoneExits[zone] ?? Config.defaultExit;
