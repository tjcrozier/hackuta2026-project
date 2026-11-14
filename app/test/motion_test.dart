// Motion detection tests with fake sensor samples (50 samples per second).
import 'dart:math';

import 'package:app/services/motion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds fake samples into a detector and collects what it reports.
class Feed {
  Feed(this.detector);
  final MotionDetector detector;
  final signals = <MotionSignal>[];
  int t = 0;

  void _add(double g) {
    signals.addAll(detector.add(g, t));
    t += 20;
  }

  /// Phone lying still.
  void rest(int ms) {
    for (var i = 0; i < ms ~/ 20; i++) {
      _add(1.0 + (i.isEven ? 0.005 : -0.005));
    }
  }

  /// Walking: acceleration swings around 1 g.
  void walk(int ms) {
    for (var i = 0; i < ms ~/ 20; i++) {
      _add(1.0 + 0.5 * sin(i * 0.6));
    }
  }

  void freeFall(int ms) {
    for (var i = 0; i < ms ~/ 20; i++) {
      _add(0.05);
    }
  }

  void impact([double g = 4.5]) {
    _add(g);
    _add(2.0);
  }

  int count(MotionSignal signal) => signals.where((s) => s == signal).length;
}

void main() {
  // Short no-move time is off by default in these tests (1 hour) unless a test sets it.
  MotionDetector detector({int noMoveMs = 3600000}) => MotionDetector(noMoveMs: noMoveMs);

  group('shock', () {
    test('one hard hit sends one shock', () {
      final feed = Feed(detector())
        ..rest(1000)
        ..impact()
        ..rest(1000);
      expect(feed.signals, [MotionSignal.shock]);
    });

    test('a second hit within 10 s is not sent again', () {
      final feed = Feed(detector())
        ..impact()
        ..rest(5000)
        ..impact();
      expect(feed.count(MotionSignal.shock), 1);
    });

    test('a hit after 10 s is sent again', () {
      final feed = Feed(detector())
        ..impact()
        ..rest(10000)
        ..impact();
      expect(feed.count(MotionSignal.shock), 2);
    });

    test('a soft bump is not a shock', () {
      final feed = Feed(detector())
        ..rest(500)
        ..impact(2.5)
        ..rest(500);
      expect(feed.signals, isEmpty);
    });
  });

  group('fall', () {
    test('free fall, impact, then 10 s still = fall', () {
      final feed = Feed(detector())
        ..walk(2000)
        ..freeFall(300)
        ..impact()
        ..rest(9000);
      expect(feed.count(MotionSignal.fall), 0, reason: 'not yet 10 s');
      feed.rest(1500);
      expect(feed.count(MotionSignal.fall), 1);
      expect(feed.count(MotionSignal.shock), 1);
      feed.rest(20000);
      expect(feed.count(MotionSignal.fall), 1, reason: 'reported once');
    });

    test('getting up after the impact cancels the fall', () {
      final feed = Feed(detector())
        ..freeFall(300)
        ..impact()
        ..rest(3000)
        ..walk(3000)
        ..rest(10000);
      expect(feed.count(MotionSignal.fall), 0);
    });

    test('a very short drop (100 ms) is not a fall', () {
      final feed = Feed(detector())
        ..rest(500)
        ..freeFall(100)
        ..impact()
        ..rest(12000);
      expect(feed.count(MotionSignal.fall), 0);
    });

    test('an impact more than 1 s after the free fall is not a fall', () {
      final feed = Feed(detector())
        ..freeFall(300)
        ..rest(1500)
        ..impact()
        ..rest(12000);
      expect(feed.count(MotionSignal.fall), 0);
    });

    test('an impact with no free fall is only a shock', () {
      final feed = Feed(detector())
        ..rest(500)
        ..impact()
        ..rest(12000);
      expect(feed.signals, [MotionSignal.shock]);
    });
  });

  group('no movement', () {
    test('still for the whole time asks once', () {
      final feed = Feed(detector(noMoveMs: 60000))..rest(59000);
      expect(feed.count(MotionSignal.noMove), 0);
      feed.rest(2000);
      expect(feed.count(MotionSignal.noMove), 1);
      feed.rest(120000);
      expect(feed.count(MotionSignal.noMove), 1);
    });

    test('walking never asks', () {
      final feed = Feed(detector(noMoveMs: 60000))..walk(180000);
      expect(feed.count(MotionSignal.noMove), 0);
    });

    test('moving again, or answering OK, starts the timer again', () {
      final feed = Feed(detector(noMoveMs: 60000))
        ..rest(61000)
        ..walk(2000)
        ..rest(61000);
      expect(feed.count(MotionSignal.noMove), 2);

      feed.detector.resetNoMove(feed.t);
      feed.rest(30000);
      expect(feed.count(MotionSignal.noMove), 2);
      feed.rest(31000);
      expect(feed.count(MotionSignal.noMove), 3);
    });

    test('isMoving follows recent movement', () {
      final feed = Feed(detector())..walk(2000);
      expect(feed.detector.isMoving(feed.t), isTrue);
      feed.rest(20000);
      expect(feed.detector.isMoving(feed.t), isFalse);
    });
  });
}
