import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

/// In Rescue Mode, a worker phone that has not answered "safe" advertises over Bluetooth
/// so a rescuer's phone can find it (see finder.dart).
///
/// The worker id is carried twice: in the local name (BB-W-w15) and in the service UUID,
/// because iOS can cut the local name short.
///
/// iOS limit: this only works reliably while the app is open on screen.
class RescueBeacon {
  static const namePrefix = 'BB-W-';
  static const _uuidStart = 'b1acb0c5-0001-4000-8000-';

  /// "w15" -> b1acb0c5-0001-4000-8000-000000000015. Null if the id is not "w" + number.
  static String? uuidFor(String workerId) {
    final match = RegExp(r'^w(\d{1,12})$').firstMatch(workerId);
    return match == null ? null : '$_uuidStart${match.group(1)!.padLeft(12, '0')}';
  }

  /// The worker id inside one of our service UUIDs, or null.
  static String? workerIdFromUuid(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.length != 36 || !lower.startsWith(_uuidStart)) return null;
    final number = int.tryParse(lower.substring(_uuidStart.length));
    return number == null ? null : 'w$number';
  }

  /// The worker id inside a name like "BB-W-w15", or null.
  static String? workerIdFromName(String name) =>
      name.startsWith(namePrefix) && name.length > namePrefix.length
          ? name.substring(namePrefix.length)
          : null;

  /// Start advertising. Returns false if Bluetooth refused (off or not allowed).
  static Future<bool> start(String workerId) async {
    if (kIsWeb) return false;
    try {
      final peripheral = FlutterBlePeripheral();
      await peripheral.stop().catchError((_) => PeripheralBluetoothState.unknown);
      await peripheral.start(
        advertiseData: AdvertiseDataCore(
          serviceUuid: uuidFor(workerId),
          localName: '$namePrefix$workerId',
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await FlutterBlePeripheral().stop();
    } catch (_) {}
  }
}
