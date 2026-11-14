import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Floor number from air pressure. Ground floor is 1.
/// Air pressure drops about 0.12 hPa per meter, and a floor is about 3.5 m.
int floorFromPressure({required double groundHpa, required double nowHpa}) {
  final metersUp = (groundHpa - nowHpa) / Config.hpaPerM;
  return 1 + (metersUp / Config.floorHeightM).round();
}

/// The ground pressure that makes `nowHpa` read as `floor`. Used for manual correction.
double groundPressureFor({required int floor, required double nowHpa}) =>
    nowHpa + (floor - 1) * Config.floorHeightM * Config.hpaPerM;

/// Tracks the worker's floor. Uses the barometer when the phone has one;
/// otherwise the worker sets the floor by hand.
class FloorService extends ChangeNotifier {
  FloorService(this._prefs) {
    // The ground pressure is NOT saved: weather changes it from day to day.
    floor = _prefs.getInt(_floorKey) ?? 1;
  }

  static const _floorKey = 'floor_manual';

  final SharedPreferences _prefs;
  StreamSubscription<BarometerEvent>? _subscription;
  double? _ground; // pressure on the ground floor
  double? _now; // smoothed current pressure

  int floor = 1;
  bool hasBarometer = false;

  void start() {
    if (kIsWeb || !Config.featureBarometer || _subscription != null) return;
    try {
      _subscription = barometerEventStream(samplingPeriod: const Duration(seconds: 1)).listen(
        (event) => _onPressure(event.pressure),
        onError: (_) => _noBarometer(),
        cancelOnError: true,
      );
    } catch (_) {
      _noBarometer();
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _noBarometer() {
    _subscription = null;
    if (hasBarometer) {
      hasBarometer = false;
      notifyListeners();
    }
  }

  void _onPressure(double hpa) {
    // Smooth the readings a little so the floor does not flicker.
    _now = _now == null ? hpa : _now! * 0.8 + hpa * 0.2;
    final firstReading = !hasBarometer;
    hasBarometer = true;
    // First time ever: keep the floor the worker last had.
    _ground ??= groundPressureFor(floor: floor, nowHpa: _now!);
    final newFloor = floorFromPressure(groundHpa: _ground!, nowHpa: _now!);
    if (newFloor != floor || firstReading) {
      floor = newFloor;
      notifyListeners();
    }
  }

  /// "I'm on the ground floor" button.
  void calibrateGround() => setFloor(1);

  /// Manual correction: tell the app which floor this is right now.
  void setFloor(int newFloor) {
    floor = newFloor;
    _prefs.setInt(_floorKey, newFloor);
    if (_now != null) {
      _ground = groundPressureFor(floor: newFloor, nowHpa: _now!);
    }
    notifyListeners();
  }
}
