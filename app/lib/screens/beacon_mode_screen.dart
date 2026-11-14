import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../services/zone_beacon.dart';
import '../theme.dart';
import '../widgets/status_pill.dart';

/// Zone beacon: this device sits in a zone and advertises "BB-ZONE-A" over Bluetooth.
class BeaconModeScreen extends StatefulWidget {
  const BeaconModeScreen({super.key});

  @override
  State<BeaconModeScreen> createState() => _BeaconModeScreenState();
}

class _BeaconModeScreenState extends State<BeaconModeScreen> {
  String _zone = Config.zones.first;
  bool _on = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {}); // the beacon only works with the screen on
    _start(_zone);
  }

  @override
  void dispose() {
    ZoneBeacon.stopAdvertising();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _start(String zone) async {
    setState(() {
      _zone = zone;
      _on = false;
      _error = null;
    });
    try {
      await ZoneBeacon.advertise(zone);
      if (mounted && _zone == zone) setState(() => _on = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Bluetooth could not start. Turn Bluetooth on and allow it.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: BB.ink,
        appBar: AppBar(
          backgroundColor: BB.ink,
          foregroundColor: BB.white,
          title: Text('Zone beacon', style: heading(20, color: BB.white)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _on
                    ? const StatusPill('Sending signal', kind: PillKind.safe, icon: Icons.sensors)
                    : StatusPill(_error == null ? 'Starting' : 'Not sending',
                        kind: _error == null ? PillKind.neutral : PillKind.hazard),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('ZONE', style: heading(22, color: BB.line)),
                        FittedBox(child: Text(_zone, style: heading(260, color: BB.white))),
                        Text('${Config.zoneNamePrefix}$_zone',
                            style: body(15, color: BB.line)),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center, style: body(15, color: BB.white)),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    for (final zone in Config.zones)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            height: 64,
                            child: FilledButton(
                              onPressed: () => _start(zone),
                              style: FilledButton.styleFrom(
                                backgroundColor: zone == _zone ? BB.white : BB.muted,
                                foregroundColor: zone == _zone ? BB.ink : BB.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text(zone,
                                  style: heading(24,
                                      color: zone == _zone ? BB.ink : BB.white)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Keep this screen open. The screen stays on.',
                    textAlign: TextAlign.center, style: body(14, color: BB.line)),
              ],
            ),
          ),
        ),
      );
}
