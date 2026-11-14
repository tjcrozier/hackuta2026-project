// Mesh rules: dedupe, hops (ttl), path, forwarding, and the offline collapse check.
import 'package:app/models/mesh_message.dart';
import 'package:app/services/mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MeshMessage fromA() =>
      MeshRouter('w1').originate(msgId: 'm1', type: 'help', body: 'I need help', nowSeconds: 100);

  test('a new message starts with 5 hops and the sender in the path', () {
    final message = fromA();
    expect(message.ttl, 5);
    expect(message.path, ['w1']);
    expect(message.originWorkerId, 'w1');
  });

  test('A to B to C: each phone adds itself to the path and uses one hop', () {
    final atB = MeshRouter('w2').accept(fromA())!;
    expect(atB.path, ['w1', 'w2']);
    expect(atB.ttl, 4);
    final atC = MeshRouter('w3').accept(atB)!;
    expect(atC.path, ['w1', 'w2', 'w3']);
    expect(atC.ttl, 3);
    expect(pathText(atC.path, (id) => {'w1': 'Sajid', 'w2': 'Maria'}[id] ?? 'You'),
        'Sajid → Maria → You');
  });

  test('a message seen before is dropped (also when it comes back around)', () {
    final b = MeshRouter('w2');
    final kept = b.accept(fromA());
    expect(kept, isNotNull);
    expect(b.accept(fromA()), isNull);
    expect(b.accept(kept!.hop('w3')), isNull);
  });

  test('the sender drops its own message when a peer sends it back', () {
    final a = MeshRouter('w1');
    final message = a.originate(msgId: 'm1', type: 'text', nowSeconds: 100);
    expect(a.accept(message.hop('w2')), isNull);
  });

  test('a message with no hops left is dropped', () {
    final spent = MeshMessage(
        msgId: 'm9', originWorkerId: 'w1', type: 'text', createdAt: 100, ttl: 0, path: ['w1']);
    expect(MeshRouter('w2').accept(spent), isNull);
  });

  test('the last hop is kept and shown, but not passed on', () {
    final lastHop = MeshMessage(
        msgId: 'm9', originWorkerId: 'w1', type: 'text', createdAt: 100, ttl: 1, path: ['w1']);
    final kept = MeshRouter('w2').accept(lastHop)!;
    expect(kept.ttl, 0);
    expect(MeshRouter.shouldForward(kept), isFalse);
    expect(MeshRouter.shouldForward(MeshRouter('w2').accept(fromA())!), isTrue);
  });

  test('stored messages are remembered after a restart', () {
    final router = MeshRouter('w2')..remember('m1');
    expect(router.accept(fromA()), isNull);
  });

  test('json round trip matches the contract field names', () {
    final json = fromA().toJson();
    expect(json.keys, containsAll(['msg_id', 'origin_worker_id', 'type', 'body', 'zone', 'floor',
      'battery', 'created_at', 'ttl', 'path']));
    final back = MeshMessage.fromJson(json);
    expect((back.msgId, back.type, back.body, back.ttl), ('m1', 'help', 'I need help', 5));
    expect(back.path, ['w1']);
  });

  group('offline collapse', () {
    test('own shock plus two other phones inside 5 s is a collapse', () {
      final watch = CollapseWatch('w1');
      expect(watch.addShock('w1', 0), isNull);
      expect(watch.addShock('w2', 2000), isNull);
      expect(watch.addShock('w3', 4000), 3);
    });

    test('three phones spread over 6 s is not a collapse', () {
      final watch = CollapseWatch('w1');
      watch.addShock('w1', 0);
      watch.addShock('w2', 3000);
      expect(watch.addShock('w3', 6000), isNull);
    });

    test('other phones without this phone feeling it is not a collapse here', () {
      final watch = CollapseWatch('w1');
      watch.addShock('w2', 0);
      watch.addShock('w3', 1000);
      expect(watch.addShock('w4', 2000), isNull);
    });

    test('one phone shaking many times is not a collapse', () {
      final watch = CollapseWatch('w1');
      expect([for (var t = 0; t < 4000; t += 1000) watch.addShock('w1', t)],
          everyElement(isNull));
    });
  });
}
