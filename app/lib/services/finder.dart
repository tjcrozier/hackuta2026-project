import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'rescue_beacon.dart';

// ---- Pure signal helpers (unit-tested) ----

/// Smooths jumpy signal readings: new value = 70% old + 30% new reading.
class RssiSmoother {
  double? value;

  double add(int rssi) => value = value == null ? rssi.toDouble() : value! * 0.7 + rssi * 0.3;
}

/// "Far", "Getting closer", "Close" or "Very close" for a signal strength in dBm.
String signalLabel(double rssi) {
  if (rssi > -60) return 'Very close';
  if (rssi >= -70) return 'Close';
  if (rssi >= -85) return 'Getting closer';
  return 'Far';
}

/// A rough distance, always as a range. Signal strength is not an exact distance.
String distanceRange(double rssi) {
  if (rssi > -60) return 'under 2 m';
  if (rssi >= -70) return 'about 2–5 m';
  if (rssi >= -85) return 'about 5–10 m';
  return 'more than 10 m';
}

/// How full the ring is: 0 at -100 dBm (far), 1 at -40 dBm (touching).
double ringFill(double rssi) => ((rssi + 100) / 60).clamp(0.0, 1.0);

/// Time between beeps: slow when far (1.2 s), fast when very close (0.15 s).
int beepIntervalMs(double rssi) => (1200 - 1050 * ringFill(rssi)).round();

// ---- Scanner ----

/// One worker phone heard by the finder.
class FoundPhone {
  FoundPhone(this.workerId);
  final String workerId;
  final _smoother = RssiSmoother();
  double rssi = -100; // smoothed
  DateTime lastHeard = DateTime.now();

  /// No signal for a few seconds: probably out of range.
  bool get lost => DateTime.now().difference(lastHeard) > const Duration(seconds: 6);
}

/// Scans all the time for worker phones advertising BB-W-* and tracks their signal.
class Finder extends ChangeNotifier {
  /// True while a finder is scanning (the zone scanner pauses so they do not fight).
  static bool active = false;

  final phones = <String, FoundPhone>{};
  String? error; // why scanning is not working, in plain words
  StreamSubscription<List<ScanResult>>? _results;
  StreamSubscription<BluetoothAdapterState>? _adapter;
  bool _disposed = false;

  void start() {
    if (kIsWeb) {
      error = 'The finder only works in the iPhone app.';
      return;
    }
    active = true;
    // Start (or restart) scanning whenever Bluetooth turns on.
    _adapter = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _scan();
      } else if (state == BluetoothAdapterState.unauthorized) {
        _fail('Bluetooth is not allowed. Turn it on in Settings > Cycl0ps.');
      } else if (state == BluetoothAdapterState.off) {
        _fail('Bluetooth is off. Turn it on to find phones.');
      }
    }, onError: (_) => _fail('Bluetooth is not available on this device.'));
  }

  Future<void> _scan() async {
    try {
      await _results?.cancel();
      _results = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final workerId = _workerIdOf(result);
          if (workerId == null) continue;
          final phone = phones.putIfAbsent(workerId, () => FoundPhone(workerId));
          phone.rssi = phone._smoother.add(result.rssi);
          phone.lastHeard = DateTime.now();
        }
        if (!_disposed) notifyListeners();
      });
      // continuousUpdates: keep reporting the same phone, so the meter moves as you walk.
      await FlutterBluePlus.startScan(continuousUpdates: true);
      error = null;
      if (!_disposed) notifyListeners();
    } catch (_) {
      _fail('Could not start the Bluetooth scan.');
    }
  }

  void _fail(String message) {
    error = message;
    if (!_disposed) notifyListeners();
  }

  static String? _workerIdOf(ScanResult result) {
    for (final uuid in result.advertisementData.serviceUuids) {
      final id = RescueBeacon.workerIdFromUuid(uuid.str128);
      if (id != null) return id;
    }
    return RescueBeacon.workerIdFromName(result.advertisementData.advName);
  }

  @override
  void dispose() {
    _disposed = true;
    active = false;
    _adapter?.cancel();
    _results?.cancel();
    if (!kIsWeb) FlutterBluePlus.stopScan().catchError((_) {});
    super.dispose();
  }
}
