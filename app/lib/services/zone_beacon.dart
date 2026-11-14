import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config.dart';
import 'finder.dart';

/// Zones without hardware: a spare iPhone/iPad advertises "BB-ZONE-A" over Bluetooth,
/// and worker phones pick the strongest beacon they can hear.
///
/// The zone is carried twice: in the local name (BB-ZONE-A) and in the service UUID.
/// iOS sometimes cuts the local name short, so the UUID is the one we trust.
class ZoneBeacon {
  static const _uuidStart = 'b1acb0c5-0000-4000-8000-0000000000';

  /// Zone "A" -> ...0041 (41 is the letter A in hex).
  static String uuidFor(String zone) =>
      '$_uuidStart${zone.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}';

  /// The zone letter inside a service UUID, or null if it is not one of ours.
  static String? zoneFromUuid(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.length != 36 || !lower.startsWith(_uuidStart)) return null;
    final code = int.tryParse(lower.substring(34), radix: 16);
    final zone = code == null ? null : String.fromCharCode(code);
    return Config.zones.contains(zone) ? zone : null;
  }

  /// The zone letter inside a name like "BB-ZONE-A", or null.
  static String? zoneFromName(String name) {
    if (!name.startsWith(Config.zoneNamePrefix)) return null;
    final zone = name.substring(Config.zoneNamePrefix.length);
    return Config.zones.contains(zone) ? zone : null;
  }

  /// Picks the zone with the strongest average signal. `readings` is zone -> RSSI list.
  static String? strongest(Map<String, List<int>> readings) {
    String? best;
    var bestAverage = double.negativeInfinity;
    readings.forEach((zone, values) {
      if (values.isEmpty) return;
      final average = values.reduce((a, b) => a + b) / values.length;
      if (average > bestAverage) {
        bestAverage = average;
        best = zone;
      }
    });
    return best;
  }

  static bool _scanning = false;

  /// Scans for a few seconds and returns the nearest zone, or null if none was heard
  /// (or Bluetooth is off / not allowed). Never throws.
  static Future<String?> scan() async {
    if (kIsWeb || !Config.featureZoneBeacons || _scanning || Finder.active) return null;
    _scanning = true;
    final readings = <String, List<int>>{};
    StreamSubscription<List<ScanResult>>? subscription;
    try {
      // Wait a moment for Bluetooth to report that it is on.
      await FlutterBluePlus.adapterState
          .firstWhere((state) => state == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 3));
      subscription = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final zone = _zoneOf(result);
          if (zone != null) readings.putIfAbsent(zone, () => []).add(result.rssi);
        }
      });
      const duration = Duration(seconds: Config.zoneScanSeconds);
      await FlutterBluePlus.startScan(timeout: duration, continuousUpdates: true);
      await Future<void>.delayed(duration + const Duration(milliseconds: 300));
    } catch (_) {
      // Bluetooth off, not allowed, or not supported: the app falls back to the manual picker.
    } finally {
      await subscription?.cancel();
      _scanning = false;
    }
    return strongest(readings);
  }

  static String? _zoneOf(ScanResult result) {
    for (final uuid in result.advertisementData.serviceUuids) {
      final zone = zoneFromUuid(uuid.str128);
      if (zone != null) return zone;
    }
    return zoneFromName(result.advertisementData.advName);
  }

  /// Beacon mode: start advertising as a zone. Throws if Bluetooth refuses.
  static Future<void> advertise(String zone) async {
    final peripheral = FlutterBlePeripheral();
    await peripheral.stop().catchError((_) => PeripheralBluetoothState.unknown);
    await peripheral.start(
      advertiseData: AdvertiseDataCore(
        serviceUuid: uuidFor(zone),
        localName: '${Config.zoneNamePrefix}$zone',
      ),
    );
  }

  static Future<void> stopAdvertising() async {
    try {
      await FlutterBlePeripheral().stop();
    } catch (_) {}
  }
}
