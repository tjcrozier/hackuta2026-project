// Unit tests for the pure logic (no plugins, no network).
import 'package:app/models/snapshot.dart';
import 'package:app/screens/supervisor_rescue.dart';
import 'package:app/screens/web/rescuer_screen.dart';
import 'package:app/services/floor.dart';
import 'package:app/services/live_socket.dart';
import 'package:app/services/zone_beacon.dart';
import 'package:app/widgets/floor_map.dart';
import 'package:app/widgets/floor_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('floor from pressure', () {
    test('same pressure is the ground floor', () {
      expect(floorFromPressure(groundHpa: 1013.0, nowHpa: 1013.0), 1);
    });

    test('one floor up is 3.5 m, about 0.42 hPa lower', () {
      expect(floorFromPressure(groundHpa: 1013.0, nowHpa: 1013.0 - 0.42), 2);
      expect(floorFromPressure(groundHpa: 1013.0, nowHpa: 1013.0 - 0.84), 3);
    });

    test('small changes (holding the phone higher) keep the same floor', () {
      expect(floorFromPressure(groundHpa: 1013.0, nowHpa: 1013.0 - 0.15), 1);
    });

    test('manual correction round-trips', () {
      final ground = groundPressureFor(floor: 3, nowHpa: 1010.0);
      expect(floorFromPressure(groundHpa: ground, nowHpa: 1010.0), 3);
    });
  });

  group('zone beacon', () {
    test('uuid carries the zone letter', () {
      for (final zone in ['A', 'B', 'C']) {
        expect(ZoneBeacon.zoneFromUuid(ZoneBeacon.uuidFor(zone)), zone);
      }
      expect(ZoneBeacon.uuidFor('A'), 'b1acb0c5-0000-4000-8000-000000000041');
      expect(ZoneBeacon.zoneFromUuid('0000180f-0000-1000-8000-00805f9b34fb'), isNull);
    });

    test('name carries the zone letter', () {
      expect(ZoneBeacon.zoneFromName('BB-ZONE-B'), 'B');
      expect(ZoneBeacon.zoneFromName('BB-ZONE-Z'), isNull);
      expect(ZoneBeacon.zoneFromName('AirPods'), isNull);
    });

    test('strongest average signal wins', () {
      expect(
        ZoneBeacon.strongest({
          'A': [-80, -78, -82],
          'B': [-60, -64],
        }),
        'B',
      );
      expect(ZoneBeacon.strongest({}), isNull);
    });
  });

  test('live socket address', () {
    expect(LiveSocket.liveUri('http://192.168.1.20:8000').toString(), 'ws://192.168.1.20:8000/live');
    expect(LiveSocket.liveUri('https://x.trycloudflare.com').toString(),
        'wss://x.trycloudflare.com/live');
  });

  test('snapshot parsing', () {
    final snapshot = Snapshot.fromJson({
      'site': {'name': 'Arlington Site', 'code': 'ARL-0412'},
      'rescue': {'active': true, 'reason': 'impact on 3 phones', 'started_at': 1},
      'workers': [
        {'id': 'w1', 'name': 'Sajid H.', 'zone': 'B', 'floor': 3, 'battery': 64,
         'last_ping': 1763060000, 'moving': true, 'source': 'internet',
         'status': 'help', 'phone_lost': false},
        {'id': 'w2', 'name': 'New', 'zone': null, 'floor': null, 'battery': null,
         'last_ping': null, 'moving': false, 'source': null, 'status': 'none',
         'phone_lost': false},
      ],
      'hazards': [
        {'id': 1, 'floor': 3, 'text': 'New opening', 'osha_topic': 'Fall protection',
         'status': 'open', 'ts': 0},
      ],
      'scans': {},
      'messages': [],
    });
    expect(snapshot.rescueActive, isTrue);
    expect(snapshot.workers.first.status, 'help');
    expect(snapshot.workers.last.floor, isNull);
    expect(snapshot.hazards.single.open, isTrue);
  });

  test('snapshot scans and rescue start time', () {
    final snapshot = Snapshot.fromJson({
      'rescue': {'active': true, 'reason': 'x', 'started_at': 1763060000},
      'scans': {
        '3': {'model': 'f3.glb', 'ts': 1763000000,
              'parts': {'walls': 6, 'doors': 2, 'windows': 1, 'openings': 1}},
      },
    });
    expect(snapshot.rescueStartedAt, 1763060000);
    expect(snapshot.scans[3]!.parts['walls'], 6);
  });

  test('rescue list order: no answer, then help, then safe; higher floors first', () {
    WorkerInfo w(String name, String status, int floor) =>
        WorkerInfo(id: name, name: name, status: status, floor: floor);
    final order = SupervisorRescue.sorted([
      w('safe3', 'safe', 3),
      w('help1', 'help', 1),
      w('none1', 'none', 1),
      w('none3', 'none', 3),
      w('help2', 'help', 2),
    ]).map((worker) => worker.name).toList();
    expect(order, ['none3', 'none1', 'help2', 'help1', 'safe3']);
  });

  test('people to find first: no answer, then help, highest floor first, no safe people', () {
    WorkerInfo w(String name, String status, int? floor) =>
        WorkerInfo(id: name, name: name, status: status, floor: floor);
    final order = RescuerScreen.toFind([
      w('safe3', 'safe', 3),
      w('help1', 'help', 1),
      w('none1', 'none', 1),
      w('noneUnknown', 'none', null),
      w('none3', 'none', 3),
      w('help3', 'help', 3),
    ]).map((worker) => worker.name).toList();
    expect(order, ['none3', 'none1', 'noneUnknown', 'help3', 'help1']);
  });

  test('map dots are spread out and do not overlap', () {
    final dots = spreadDots(6, const Offset(100, 100), 23);
    expect(dots.first, const Offset(100, 100));
    for (var i = 0; i < dots.length; i++) {
      for (var j = i + 1; j < dots.length; j++) {
        expect((dots[i] - dots[j]).distance, greaterThan(20), reason: 'dots $i and $j');
      }
    }
  });

  test('known floors: scans and workers, top floor first', () {
    expect(knownFloors([1, 2], [3, null, 2]), [3, 2, 1]);
  });
}
