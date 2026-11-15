import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/athena_chat.dart' show athenaIcon;
import '../widgets/big_button.dart';
import '../widgets/offline_banner.dart';
import '../widgets/shares_box.dart';
import '../widgets/status_pill.dart';
import 'worker_rescue.dart';

/// Worker home: floor and zone, last ping, hazards here, what is shared, help button.
class WorkerHome extends StatefulWidget {
  const WorkerHome({super.key});

  @override
  State<WorkerHome> createState() => _WorkerHomeState();
}

class _WorkerHomeState extends State<WorkerHome> {
  Timer? _clock; // redraws "12 s ago" every second
  bool _helpBusy = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _ago(DateTime? time) {
    if (time == null) return 'not yet';
    final seconds = DateTime.now().difference(time).inSeconds;
    if (seconds < 5) return 'just now';
    if (seconds < 90) return '$seconds s ago';
    return '${seconds ~/ 60} min ago';
  }

  Future<void> _help(Shift shift, bool help) async {
    if (help) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Send a help request?', style: heading(20)),
          content: Text('Your supervisor gets a text with your floor and zone.', style: body(15)),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            BigButton(
              label: 'Yes, I need help',
              icon: Icons.pan_tool_outlined,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            BigButton(
              label: 'Cancel',
              outlined: true,
              height: 56,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    setState(() => _helpBusy = true);
    try {
      await shift.sendHelp(help);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not reach the server. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _helpBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<Shift>();
    if (shift.onShift && shift.rescueActive) return const WorkerRescue();
    return Scaffold(
      appBar: AppBar(
        title: Text(shift.name.isEmpty ? 'Worker' : shift.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _shiftPill(shift)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: shift.onShift ? _onShift(shift) : _offShift(shift),
        ),
      ),
    );
  }

  Widget _shiftPill(Shift shift) {
    if (!shift.onShift) return const StatusPill('Off shift');
    if (!shift.online && shift.lastPing != null) {
      return const StatusPill('No connection', kind: PillKind.hazard, icon: Icons.wifi_off);
    }
    return const StatusPill('On shift', kind: PillKind.safe);
  }

  List<Widget> _offShift(Shift shift) => [
        const SizedBox(height: 24),
        Text('You are off shift', style: heading(26)),
        const SizedBox(height: 8),
        Text('Nothing is shared until you start a shift.', style: body(16, color: BB.muted)),
        const SizedBox(height: 24),
        BigButton(
          label: 'Start shift',
          icon: Icons.play_arrow_outlined,
          height: 72,
          color: BB.safe,
          onPressed: shift.startShift,
        ),
        const SizedBox(height: 16),
        const SharesBox(),
      ];

  List<Widget> _onShift(Shift shift) => [
        if ((!shift.online && shift.lastPing != null) || shift.offlineMode) ...[
          const OfflineBanner(
            showSavedTime: false,
            message: 'Your phone keeps working: fall checks, the help button and the '
                'offline mesh still work.',
          ),
          const SizedBox(height: 12),
        ],
        _whereCard(shift),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _fact(Icons.schedule_outlined, 'Last ping', _ago(shift.lastPing))),
            const SizedBox(width: 12),
            Expanded(
              child: _fact(Icons.battery_std_outlined, 'Battery',
                  shift.battery == null ? 'unknown' : '${shift.battery}%'),
            ),
          ],
        ),
        for (final hazard in shift.hazardsHere) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.report_problem_outlined, color: BB.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hazard on your floor',
                          style: body(13, color: BB.accent, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(hazard.text, style: body(16, weight: FontWeight.w600)),
                      if (hazard.oshaTopic.isNotEmpty)
                        Text(hazard.oshaTopic, style: body(13, color: BB.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        SharesBox(zone: shift.zone ?? 'unknown', floor: shift.floor.floor, battery: shift.battery),
        const SizedBox(height: 16),
        if (shift.helpSent) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: BB.help, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.pan_tool_outlined, color: BB.helpText, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Help request sent to your supervisor.',
                      style: body(16, color: BB.helpText, weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'I\'m OK now',
            icon: Icons.check_circle_outline,
            color: BB.safe,
            busy: _helpBusy,
            onPressed: () => _help(shift, false),
          ),
        ] else
          BigButton(
            label: 'I need help',
            icon: Icons.pan_tool_outlined,
            height: 84,
            busy: _helpBusy,
            onPressed: () => _help(shift, true),
          ),
        const SizedBox(height: 12),
        _meshRow(shift),
        const SizedBox(height: 12),
        if (Config.featureAthena) ...[
          BigButton(
            label: 'Ask Athena',
            icon: athenaIcon,
            outlined: true,
            height: 56,
            onPressed: () => context.push('/athena?role=worker'),
          ),
          const SizedBox(height: 12),
        ],
        BigButton(
          label: 'End shift',
          icon: Icons.logout_outlined,
          outlined: true,
          height: 56,
          onPressed: shift.endShift,
        ),
      ];

  /// Offline mesh status. Tap to open the mesh screen.
  Widget _meshRow(Shift shift) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/mesh'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: cardBox(),
          child: Row(
            children: [
              const Icon(Icons.hub_outlined, color: BB.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline mesh', style: body(16, weight: FontWeight.w600)),
                    Text(
                      shift.mesh.running
                          ? '${shift.mesh.peers.length} phones connected'
                          : 'Off. Turns on by itself if the internet drops.',
                      style: body(13, color: BB.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: BB.muted),
            ],
          ),
        ),
      );

  /// Dark card with the big floor number and zone letter.
  Widget _whereCard(Shift shift) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: BB.ink, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _big('FLOOR', '${shift.floor.floor}')),
                Expanded(child: _big('ZONE', shift.zone ?? '?')),
              ],
            ),
            const SizedBox(height: 6),
            Text(_zoneNote(shift), style: body(14, color: BB.line)),
            if (shift.zone == null || !shift.zoneFromBeacon) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final zone in Config.zones)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _darkButton(zone, selected: zone == shift.zone,
                            onPressed: () => shift.pickZone(zone)),
                      ),
                    ),
                ],
              ),
            ],
            const Divider(height: 28, color: BB.muted),
            Text(
              shift.floor.hasBarometer
                  ? 'Floor comes from air pressure. Fix it here if it is wrong.'
                  : 'This phone has no pressure sensor. Set your floor here.',
              style: body(14, color: BB.line),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _darkButton('I\'m on the ground floor',
                      onPressed: shift.floor.calibrateGround),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _darkButton('-',
                      label: 'Floor down',
                      onPressed: shift.floor.floor > 1
                          ? () => shift.floor.setFloor(shift.floor.floor - 1)
                          : null),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _darkButton('+',
                      label: 'Floor up',
                      onPressed: () => shift.floor.setFloor(shift.floor.floor + 1)),
                ),
              ],
            ),
          ],
        ),
      );

  String _zoneNote(Shift shift) {
    if (shift.zone == null) return 'Zone unknown — tap to pick';
    if (shift.zoneFromBeacon) return 'Zone found by a nearby beacon.';
    return 'No beacon nearby. Tap to change your zone.';
  }

  Widget _big(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: heading(14, color: BB.line, weight: FontWeight.w500)),
          Text(value, style: heading(84, color: BB.white)),
        ],
      );

  Widget _darkButton(String text,
          {required VoidCallback? onPressed, bool selected = false, String? label}) =>
      Semantics(
        label: label,
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: selected ? BB.white : BB.muted,
              foregroundColor: selected ? BB.ink : BB.white,
              disabledBackgroundColor: BB.muted.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: FittedBox(
              child: Text(text,
                  style: body(16, color: selected ? BB.ink : BB.white, weight: FontWeight.w700)),
            ),
          ),
        ),
      );

  Widget _fact(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Row(
          children: [
            Icon(icon, color: BB.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: body(13, color: BB.muted)),
                  Text(value, style: heading(18)),
                ],
              ),
            ),
          ],
        ),
      );
}
