import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config.dart';

/// What the detector can report.
enum MotionSignal { shock, fall, noMove }

/// Pure detection logic. Feed it one sample at a time: the size of the acceleration
/// in g (1.0 = resting, 0 = free fall) and the time in milliseconds.
/// No plugins here, so it can be unit-tested with fake samples.
class MotionDetector {
  MotionDetector({
    this.shockG = Config.shockG,
    this.freefallG = Config.freefallG,
    this.freefallMs = 150,
    this.impactWindowMs = 1000,
    this.settleMs = 1000,
    this.fallStillMs = Config.fallStillSec * 1000,
    this.noMoveMs = Config.noMoveMin * 60 * 1000,
    this.shockGapMs = Config.shockGapSec * 1000,
  });

  final double shockG; // above this = hard impact
  final double freefallG; // below this = falling
  final int freefallMs; // how long it must stay below freefallG
  final int impactWindowMs; // impact must come this soon after the free fall
  final int settleMs; // ignore bounces right after the impact
  final int fallStillMs; // lying still this long after the impact = a fall
  final int noMoveMs; // no movement this long = ask "Are you OK?"
  final int shockGapMs; // report a shock at most once per this time

  /// Smoothed distance from 1 g. Above this the phone counts as moving.
  static const moveThreshold = 0.06;

  /// "moving" in pings means movement in the last 15 seconds.
  static const movingWindowMs = 15000;

  bool _started = false;
  double _activity = 0; // smoothed |g - 1|
  int _lastMove = 0;
  bool _noMoveSent = false;
  int? _lastShock;
  int? _lowSince; // start of the current below-freefallG run
  int? _freeFallAt; // a real free fall was seen at this time
  int? _impactAt; // free fall was followed by an impact at this time

  List<MotionSignal> add(double g, int t) {
    final signals = <MotionSignal>[];
    if (!_started) {
      _started = true;
      _lastMove = t;
    }

    // Movement: smooth out the noise, then compare with the threshold.
    _activity = _activity * 0.9 + (g - 1).abs() * 0.1;
    final movingNow = _activity > moveThreshold;
    if (movingNow) {
      _lastMove = t;
      _noMoveSent = false;
    }

    // Shock: one hard hit. Limited to once per shockGapMs.
    final hit = g > shockG;
    if (hit && (_lastShock == null || t - _lastShock! >= shockGapMs)) {
      _lastShock = t;
      signals.add(MotionSignal.shock);
    }

    // Fall, step 1: free fall for at least freefallMs.
    if (g < freefallG) {
      _lowSince ??= t;
      if (t - _lowSince! >= freefallMs) _freeFallAt = t;
    } else {
      _lowSince = null;
    }

    // Fall, step 2: an impact soon after the free fall.
    if (_freeFallAt != null) {
      if (t - _freeFallAt! > impactWindowMs) {
        _freeFallAt = null; // too late, it was something else
      } else if (hit) {
        _impactAt = t;
        _freeFallAt = null;
      }
    }

    // Fall, step 3: lying still after the impact.
    if (_impactAt != null) {
      final sinceImpact = t - _impactAt!;
      if (sinceImpact > settleMs && movingNow) {
        _impactAt = null; // the person (or phone) is moving again: not a fall
      } else if (sinceImpact >= fallStillMs) {
        _impactAt = null;
        signals.add(MotionSignal.fall);
      }
    }

    // No movement for a long time. Reported once until there is movement again.
    if (!_noMoveSent && t - _lastMove >= noMoveMs) {
      _noMoveSent = true;
      signals.add(MotionSignal.noMove);
    }
    return signals;
  }

  bool isMoving(int t) => !_started || t - _lastMove < movingWindowMs;

  /// Call after the worker answers "I'm OK" so the no-movement timer starts again.
  void resetNoMove(int t) {
    _lastMove = t;
    _noMoveSent = false;
  }
}

/// Connects the phone's accelerometer to the detector. Raw sensor data never leaves the phone.
class MotionService {
  MotionService({required this.onSignal});

  final void Function(MotionSignal signal) onSignal;
  MotionDetector _detector = MotionDetector();
  StreamSubscription<AccelerometerEvent>? _subscription;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  void start() {
    if (kIsWeb || !Config.featureMotion || _subscription != null) return;
    _detector = MotionDetector();
    try {
      _subscription = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (event) {
          final g = sqrt(event.x * event.x + event.y * event.y + event.z * event.z) / 9.80665;
          for (final signal in _detector.add(g, _now())) {
            onSignal(signal);
          }
        },
        onError: (_) {}, // no accelerometer (simulator): motion safety is simply off
        cancelOnError: true,
      );
    } catch (_) {}
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  bool get moving => _detector.isMoving(_now());

  void resetNoMove() => _detector.resetNoMove(_now());
}
