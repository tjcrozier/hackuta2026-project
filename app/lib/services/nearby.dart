import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/mesh_message.dart';
import 'mesh.dart';

// ---- Pure helpers (unit-tested) ----

/// Arrow angle in radians from a direction vector: 0 = straight ahead, positive = to the right.
/// Apple's direction has x to the right and z pointing backwards, so "ahead" is -z.
double arrowAngle(double x, double z) => atan2(x, -z);

/// "0.8 m", "3.4 m", "12 m".
String preciseDistanceText(double meters) =>
    meters < 10 ? '${meters.toStringAsFixed(1)} m' : '${meters.round()} m';

/// The latest precise measurement to one phone.
class NearbyReading {
  NearbyReading({this.distanceM, this.angle, required this.at});
  final double? distanceM;
  final double? angle; // radians, see arrowAngle; null when the phone gives no direction
  final DateTime at;

  bool get fresh => DateTime.now().difference(at) < const Duration(seconds: 3);
}

/// Bridge to Apple Nearby Interaction (ios/Runner/NearbyService.swift).
/// The two phones swap tokens over the mesh with "ni_token" messages.
class Nearby extends ChangeNotifier {
  static const _methods = MethodChannel('blackbox/nearby');
  static const _events = EventChannel('blackbox/nearby/events');

  bool supported = false; // this phone can measure precise distance
  final readings = <String, NearbyReading>{};
  StreamSubscription<dynamic>? _subscription;

  Future<void> init() async {
    if (kIsWeb || !Config.featureNearby) return;
    try {
      final caps = await _methods.invokeMapMethod<String, bool>('capabilities');
      supported = caps?['distance'] ?? false;
      if (supported) {
        _subscription = _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
      }
      notifyListeners();
    } catch (_) {
      supported = false; // simulator, or the channel is missing
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final peerId = '${event['peerId']}';
    if (event['lost'] == true) {
      readings.remove(peerId);
    } else {
      final x = (event['directionX'] as num?)?.toDouble();
      final z = (event['directionZ'] as num?)?.toDouble();
      final horizontal = (event['horizontalAngle'] as num?)?.toDouble();
      readings[peerId] = NearbyReading(
        distanceM: (event['distanceM'] as num?)?.toDouble() ?? readings[peerId]?.distanceM,
        angle: horizontal ?? (x != null && z != null ? arrowAngle(x, z) : null),
        at: DateTime.now(),
      );
    }
    notifyListeners();
  }

  /// Finder side: ask a directly connected phone to start precise finding.
  Future<void> request(Mesh mesh, String peerId) async {
    if (!supported || !mesh.peers.containsKey(peerId)) return;
    await _sendToken(mesh, peerId, wantReply: true);
  }

  /// A token message arrived over the mesh.
  Future<void> handleToken(Mesh mesh, MeshMessage message) async {
    if (!supported) return;
    try {
      final body = Map<String, dynamic>.from(jsonDecode(message.body) as Map);
      if (body['to'] != mesh.selfId) return; // meant for another phone
      final peerId = message.originWorkerId;
      // Send our own token back first, then start measuring.
      if (body['reply'] == true) await _sendToken(mesh, peerId, wantReply: false);
      await _methods.invokeMethod('setPeerToken', {
        'peerId': peerId,
        'token': body['token'],
        'cameraAssist': Config.nearbyCameraAssist,
      });
    } catch (_) {}
  }

  Future<void> _sendToken(Mesh mesh, String peerId, {required bool wantReply}) async {
    try {
      final token = await _methods.invokeMethod<String>('myToken', {'peerId': peerId});
      if (token == null) return;
      mesh.sendDirect('ni_token', jsonEncode({'to': peerId, 'token': token, 'reply': wantReply}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> stop() async {
    readings.clear();
    if (!supported) return;
    try {
      await _methods.invokeMethod('stop');
    } catch (_) {}
  }
}
