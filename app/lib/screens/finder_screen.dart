import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/snapshot.dart';
import '../services/finder.dart';
import '../services/nearby.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/live_builder.dart';
import '../widgets/status_pill.dart';

/// Rescuer finder: lists worker phones heard over Bluetooth, and a "hot and cold"
/// meter for one phone. It shows signal strength, not exact distance.
class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  final _finder = Finder();
  final _player = AudioPlayer();
  Timer? _beep;
  String? _target; // worker id being tracked on the meter, or null for the list
  bool _muted = false;

  // Precise finding (Nearby Interaction). Tokens are swapped over the mesh, so the mesh
  // is switched on while the finder is open.
  late final Shift _shift = context.read<Shift>();
  Timer? _preciseRetry;
  bool _meshWasOn = false;

  @override
  void initState() {
    super.initState();
    _finder.addListener(_changed);
    _finder.start();
    _shift.nearby.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shift.nearby.supported) return;
      _meshWasOn = _shift.offlineMode;
      _shift.setOfflineMode(true);
      // Keep asking the phone we are looking for until measurements arrive.
      _preciseRetry = Timer.periodic(const Duration(seconds: 3), (_) => _askPrecise());
    });
  }

  void _askPrecise() {
    final target = _target;
    if (target == null || _shift.nearby.readings[target]?.fresh == true) return;
    _shift.nearby.request(_shift.mesh, target);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _preciseRetry?.cancel();
    _shift.nearby.removeListener(_changed);
    _shift.nearby.stop();
    if (_shift.nearby.supported && !_meshWasOn) {
      // Not during this frame: other screens are still being torn down.
      final shift = _shift;
      Future.microtask(() => shift.setOfflineMode(false));
    }
    _beep?.cancel();
    _player.dispose();
    _finder.removeListener(_changed);
    _finder.dispose();
    super.dispose();
  }

  void _open(String? workerId) {
    setState(() => _target = workerId);
    _beep?.cancel();
    if (workerId != null) {
      _scheduleBeep();
      _askPrecise();
    }
  }

  /// Beeps again and again; the gap gets shorter as the signal gets stronger.
  void _scheduleBeep() {
    final phone = _finder.phones[_target];
    final gap = phone == null || phone.lost ? 1500 : beepIntervalMs(phone.rssi);
    _beep = Timer(Duration(milliseconds: gap), () async {
      if (!mounted || _target == null) return;
      final current = _finder.phones[_target];
      if (current != null && !current.lost) {
        HapticFeedback.selectionClick();
        if (!_muted) {
          try {
            await _player.stop();
            await _player.play(AssetSource('beep.wav'));
          } catch (_) {
            // No sound is fine: the ring and the vibration still work.
          }
        }
      }
      _scheduleBeep();
    });
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(builder: (context, live) {
        final workers = {
          for (final w in live.snapshot?.workers ?? const <WorkerInfo>[]) w.id: w,
        };
        final target = _target;
        return Scaffold(
          appBar: AppBar(
            title: Text(target == null ? 'Rescuer finder' : workers[target]?.name ?? 'Worker $target'),
            leading: target == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back to the list',
                    onPressed: () => _open(null),
                  ),
          ),
          body: SafeArea(
            child: target == null
                ? _list(workers, live.snapshot)
                : _meter(_finder.phones[target], workers[target], _shift.nearby.readings[target]),
          ),
        );
      });

  // ---------- list ----------

  Widget _list(Map<String, WorkerInfo> workers, Snapshot? snapshot) {
    final heard = _finder.phones.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    // Missing people whose phone has not been heard yet.
    final notHeard = snapshot == null || !snapshot.rescueActive
        ? <WorkerInfo>[]
        : snapshot.workers
            .where((w) => w.status != 'safe' && !_finder.phones.containsKey(w.id))
            .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (_finder.error != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_disabled_outlined, color: BB.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(_finder.error!, style: body(15, weight: FontWeight.w600))),
              ],
            ),
          ),
        Text('Phones nearby', style: heading(20)),
        const SizedBox(height: 4),
        Text('Walk slowly. Tap a name to follow its signal.', style: body(15, color: BB.muted)),
        const SizedBox(height: 12),
        if (heard.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardBox(),
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3, color: BB.ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Listening for worker phones...',
                      style: body(16, weight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        for (final phone in heard) _heardCard(phone, workers[phone.workerId]),
        if (notHeard.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Missing, not in range yet (${notHeard.length})', style: heading(17)),
          const SizedBox(height: 8),
          for (final worker in notHeard)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: cardBox(color: BB.ground),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(worker.name, style: body(16, weight: FontWeight.w700)),
                        Text(
                          worker.floor == null
                              ? 'Last seen: unknown'
                              : 'Last seen: Floor ${worker.floor}, Zone ${worker.zone ?? 'unknown'}',
                          style: body(13, color: BB.muted),
                        ),
                      ],
                    ),
                  ),
                  _statusPill(worker),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text('Signal strength, not exact distance.', style: body(13, color: BB.muted)),
      ],
    );
  }

  Widget _heardCard(FoundPhone phone, WorkerInfo? worker) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: BB.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BB.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(phone.workerId),
            child: Container(
              constraints: const BoxConstraints(minHeight: 84),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      value: phone.lost ? 0 : ringFill(phone.rssi),
                      strokeWidth: 6,
                      color: BB.ink,
                      backgroundColor: BB.line,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(worker?.name ?? 'Worker ${phone.workerId}', style: heading(19)),
                        const SizedBox(height: 2),
                        Text(
                          phone.lost
                              ? 'Signal lost'
                              : '${signalLabel(phone.rssi)}, ${distanceRange(phone.rssi)}',
                          style: body(14, color: BB.muted, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (worker != null) _statusPill(worker),
                  const Icon(Icons.chevron_right, color: BB.muted),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _statusPill(WorkerInfo worker) => switch (worker.status) {
        'help' => const StatusPill('Needs help', kind: PillKind.help),
        'safe' => const StatusPill('Safe', kind: PillKind.safe),
        _ => const StatusPill('No answer', kind: PillKind.noAnswer),
      };

  // ---------- meter ----------

  /// Precise distance (and an arrow when the phone gives a direction), shown above the
  /// Bluetooth meter. Hidden when the phones do not support it or are not linked yet.
  Widget _precise(NearbyReading reading) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: BB.ink, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            if (reading.angle != null)
              Transform.rotate(
                angle: reading.angle!,
                child: const Icon(Icons.navigation, color: BB.white, size: 56),
              )
            else
              const Icon(Icons.straighten_outlined, color: BB.white, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reading.distanceM == null ? 'Measuring...' : preciseDistanceText(reading.distanceM!),
                    style: heading(40, color: BB.white),
                  ),
                  Text(
                    reading.angle != null
                        ? 'Precise distance. Follow the arrow.'
                        : 'Precise distance. No direction on this phone.',
                    style: body(13, color: BB.line),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _meter(FoundPhone? phone, WorkerInfo? worker, NearbyReading? precise) {
    final lost = phone == null || phone.lost;
    final fill = lost ? 0.0 : ringFill(phone.rssi);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          if (worker != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statusPill(worker),
                if (worker.floor != null) ...[
                  const SizedBox(width: 10),
                  Text('Last seen: Floor ${worker.floor}, Zone ${worker.zone ?? 'unknown'}',
                      style: body(14, color: BB.muted)),
                ],
              ],
            ),
          if (precise != null && precise.fresh) _precise(precise),
          Expanded(
            child: Center(
              child: LayoutBuilder(builder: (context, box) {
                final size = (box.biggest.shortestSide - 16).clamp(120.0, 340.0);
                return SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The ring fills as the signal grows.
                      SizedBox.expand(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: fill),
                          duration: const Duration(milliseconds: 350),
                          builder: (context, value, _) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: 26,
                            strokeCap: StrokeCap.round,
                            color: BB.ink,
                            backgroundColor: BB.line,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(44),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              child: Text(lost ? 'Signal lost' : signalLabel(phone.rssi),
                                  style: heading(36)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lost ? 'Move around slowly' : distanceRange(phone.rssi),
                              textAlign: TextAlign.center,
                              style: body(18, color: BB.muted, weight: FontWeight.w600),
                            ),
                            if (!lost)
                              Text('${phone.rssi.round()} dBm', style: body(13, color: BB.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          Text('Signal strength, not exact distance.',
              textAlign: TextAlign.center, style: body(15, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Walk toward where the ring fills and the beep gets faster.',
              textAlign: TextAlign.center, style: body(14, color: BB.muted)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _muted = !_muted),
              icon: Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 26),
              label: Text(_muted ? 'Sound is off. Tap to turn on' : 'Mute the beep',
                  style: heading(17)),
              style: OutlinedButton.styleFrom(
                foregroundColor: BB.ink,
                side: const BorderSide(color: BB.ink, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
