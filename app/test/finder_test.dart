// Finder signal helpers and the rescue beacon id format.
import 'dart:math';

import 'package:app/services/finder.dart';
import 'package:app/services/nearby.dart';
import 'package:app/services/rescue_beacon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signal labels follow the thresholds', () {
    expect(signalLabel(-95), 'Far');
    expect(signalLabel(-86), 'Far');
    expect(signalLabel(-85), 'Getting closer');
    expect(signalLabel(-71), 'Getting closer');
    expect(signalLabel(-70), 'Close');
    expect(signalLabel(-60), 'Close');
    expect(signalLabel(-59), 'Very close');
  });

  test('distance is always a range, never one exact number', () {
    for (final rssi in [-95.0, -80.0, -65.0, -50.0]) {
      expect(distanceRange(rssi), matches(RegExp(r'^(under|about|more than) ')));
    }
    expect(distanceRange(-80), 'about 5–10 m');
  });

  test('the ring fills and the beep speeds up as the signal grows', () {
    expect(ringFill(-110), 0);
    expect(ringFill(-40), 1);
    expect(ringFill(-30), 1);
    expect(ringFill(-60), greaterThan(ringFill(-80)));
    expect(beepIntervalMs(-100), 1200);
    expect(beepIntervalMs(-40), 150);
    expect(beepIntervalMs(-60), lessThan(beepIntervalMs(-80)));
  });

  test('smoothing: one odd reading only moves the value a little', () {
    final smoother = RssiSmoother();
    expect(smoother.add(-70), -70);
    expect(smoother.add(-40), closeTo(-61, 0.01)); // 70% of -70 + 30% of -40
    for (var i = 0; i < 20; i++) {
      smoother.add(-50);
    }
    expect(smoother.value, closeTo(-50, 0.1)); // settles on a steady signal
  });

  test('rescue beacon carries the worker id in the uuid and the name', () {
    expect(RescueBeacon.uuidFor('w15'), 'b1acb0c5-0001-4000-8000-000000000015');
    expect(RescueBeacon.workerIdFromUuid('B1ACB0C5-0001-4000-8000-000000000015'), 'w15');
    expect(RescueBeacon.uuidFor('someone'), isNull);
    // A zone beacon or another device is not a worker phone.
    expect(RescueBeacon.workerIdFromUuid('b1acb0c5-0000-4000-8000-000000000041'), isNull);
    expect(RescueBeacon.workerIdFromUuid('0000180f-0000-1000-8000-00805f9b34fb'), isNull);
    expect(RescueBeacon.workerIdFromName('BB-W-w15'), 'w15');
    expect(RescueBeacon.workerIdFromName('BB-ZONE-A'), isNull);
  });

  test('arrow angle: 0 is straight ahead, positive is to the right', () {
    expect(arrowAngle(0, -1), closeTo(0, 1e-9)); // ahead
    expect(arrowAngle(1, 0), closeTo(pi / 2, 1e-9)); // right
    expect(arrowAngle(-1, 0), closeTo(-pi / 2, 1e-9)); // left
    expect(arrowAngle(0, 1).abs(), closeTo(pi, 1e-9)); // behind
  });

  test('precise distance text', () {
    expect(preciseDistanceText(0.84), '0.8 m');
    expect(preciseDistanceText(3.44), '3.4 m');
    expect(preciseDistanceText(12.3), '12 m');
  });
}
