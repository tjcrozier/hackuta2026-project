import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/mesh_message.dart';
import 'api.dart';

// ---- Pure rules (unit-tested, no plugins) ----

/// The forwarding rules from the contract:
/// drop a message we already saw; drop it if it has no hops left; otherwise keep it
/// (with our id added to the path and one hop used) and pass it on.
class MeshRouter {
  MeshRouter(this.selfId);

  final String selfId;
  final _seen = <String>{};

  /// Mark an id as seen (used when loading stored messages after a restart).
  void remember(String msgId) => _seen.add(msgId);

  /// A new message from this phone.
  MeshMessage originate({
    required String msgId,
    required String type,
    String body = '',
    String? zone,
    int? floor,
    int? battery,
    required int nowSeconds,
  }) {
    _seen.add(msgId);
    return MeshMessage(
      msgId: msgId,
      originWorkerId: selfId,
      type: type,
      body: body,
      zone: zone,
      floor: floor,
      battery: battery,
      createdAt: nowSeconds,
      path: [selfId],
    );
  }

  /// A message arrived from a peer. Returns the copy to keep, or null to drop it.
  MeshMessage? accept(MeshMessage incoming) {
    if (_seen.contains(incoming.msgId) || incoming.ttl <= 0) return null;
    _seen.add(incoming.msgId);
    return incoming.hop(selfId);
  }

  /// Message types that go to directly connected phones only: never stored or passed on.
  static const directTypes = {'ni_token'};

  /// Pass a kept message on only if it still has hops left.
  static bool shouldForward(MeshMessage kept) => kept.ttl > 0;
}

/// Offline collapse check: this phone's own shock plus shocks from enough other
/// phones inside the time window.
class CollapseWatch {
  CollapseWatch(this.selfId,
      {this.phones = Config.collapsePhones, this.windowMs = Config.collapseWindowSec * 1000});

  final String selfId;
  final int phones;
  final int windowMs;
  final _lastShock = <String, int>{}; // phone id -> time of its last shock

  /// Record a shock. Returns how many phones felt one inside the window if that is
  /// a collapse (this phone included), otherwise null.
  int? addShock(String phoneId, int nowMs) {
    _lastShock[phoneId] = nowMs;
    _lastShock.removeWhere((_, t) => nowMs - t > windowMs);
    final count = _lastShock.length;
    return _lastShock.containsKey(selfId) && count >= phones ? count : null;
  }
}

/// "Sajid -> Maria -> You" for a message path.
String pathText(List<String> path, String Function(String id) nameOf) =>
    path.map(nameOf).join(' → ');

// ---- The mesh itself ----

/// Runs the phone-to-phone mesh (ios/Runner/MeshService.swift), keeps the messages,
/// and uploads them to the server when this phone has internet.
class Mesh extends ChangeNotifier {
  Mesh(this._prefs, this._api) {
    _names.addAll(_readMap('mesh_names'));
    _uploaded.addAll(_prefs.getStringList('mesh_uploaded') ?? const []);
    for (final raw in _prefs.getStringList('mesh_messages') ?? const <String>[]) {
      try {
        messages.add(MeshMessage.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map)));
      } catch (_) {}
    }
  }

  static const _methods = MethodChannel('blackbox/mesh');
  static const _events = EventChannel('blackbox/mesh/events');
  static const _keep = 200; // newest messages kept on the phone

  final SharedPreferences _prefs;
  final Api Function() _api;

  bool running = false;
  String selfId = '';
  final peers = <String, String>{}; // connected phones: id -> name
  final messages = <MeshMessage>[]; // oldest first
  final _names = <String, String>{}; // every name we ever learned: id -> name
  final _uploaded = <String>{}; // message ids the server already has
  String? error;

  /// Called for every new message from another phone.
  void Function(MeshMessage message)? onMessage;

  MeshRouter _router = MeshRouter('');
  StreamSubscription<dynamic>? _subscription;
  Timer? _uploadTimer;
  bool _uploading = false;

  int get waitingToUpload => messages.where((m) => !_uploaded.contains(m.msgId)).length;

  String nameOf(String id) {
    if (id == selfId) return 'You';
    final name = _names[id];
    return name == null || name.isEmpty ? id : name;
  }

  /// Remember names from the server while online, to show them later when offline.
  void learnNames(Map<String, String> names) {
    if (names.entries.every((e) => _names[e.key] == e.value)) return;
    _names.addAll(names);
    _prefs.setString('mesh_names', jsonEncode(_names));
  }

  Future<void> start({required String id, required String name, required String siteCode}) async {
    if (kIsWeb || !Config.featureMesh || (running && id == selfId)) return;
    selfId = id;
    _router = MeshRouter(id);
    messages.map((m) => m.msgId).forEach(_router.remember);
    try {
      _subscription ??= _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
      await _methods.invokeMethod('start', {'siteCode': siteCode, 'workerId': id, 'name': name});
      running = true;
      error = null;
      _uploadTimer ??= Timer.periodic(const Duration(seconds: 8), (_) => tryUpload());
    } catch (_) {
      running = false;
      error = 'The mesh could not start on this device.';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!running) return;
    running = false;
    peers.clear();
    _uploadTimer?.cancel();
    _uploadTimer = null;
    try {
      await _methods.invokeMethod('stop');
    } catch (_) {}
    notifyListeners();
  }

  /// Send a new message from this phone to every connected phone.
  MeshMessage? send({required String type, String body = '', String? zone, int? floor, int? battery}) {
    if (!running) return null;
    final message = _router.originate(
      msgId: const Uuid().v4(),
      type: type,
      body: body,
      zone: zone,
      floor: floor,
      battery: battery,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    _store(message);
    _transmit(message, except: null);
    notifyListeners();
    return message;
  }

  /// Send to directly connected phones only (one hop, not stored, not uploaded).
  void sendDirect(String type, String body) {
    if (!running) return;
    final message = MeshMessage(
      msgId: const Uuid().v4(),
      originWorkerId: selfId,
      type: type,
      body: body,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ttl: 1,
      path: [selfId],
    );
    _router.remember(message.msgId);
    _transmit(message, except: null);
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'peer_connected':
        final id = '${event['id']}';
        final name = '${event['name'] ?? ''}';
        peers[id] = name;
        if (name.isNotEmpty) learnNames({id: name});
      case 'peer_lost':
        peers.remove('${event['id']}');
      case 'message':
        _receive('${event['from']}', '${event['json']}');
      case 'error':
        error = '${event['message']}';
    }
    notifyListeners();
  }

  void _receive(String fromPeer, String json) {
    MeshMessage incoming;
    try {
      incoming = MeshMessage.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
    } catch (_) {
      return;
    }
    final kept = _router.accept(incoming);
    if (kept == null) return; // seen before, or out of hops
    if (MeshRouter.directTypes.contains(kept.type)) {
      onMessage?.call(kept);
      return;
    }
    _store(kept);
    onMessage?.call(kept);
    if (MeshRouter.shouldForward(kept)) _transmit(kept, except: fromPeer);
  }

  void _transmit(MeshMessage message, {required String? except}) {
    _methods
        .invokeMethod('send', {'json': jsonEncode(message.toJson()), 'except': except})
        .catchError((_) {});
  }

  void _store(MeshMessage message) {
    messages.add(message);
    if (messages.length > _keep) messages.removeRange(0, messages.length - _keep);
    _prefs.setStringList('mesh_messages', [for (final m in messages) jsonEncode(m.toJson())]);
  }

  /// If this phone has internet, hand the stored messages to the server.
  /// Returns true when nothing is left waiting.
  Future<bool> tryUpload() async {
    final waiting = messages.where((m) => !_uploaded.contains(m.msgId)).toList();
    if (waiting.isEmpty) return true;
    if (_uploading) return false;
    _uploading = true;
    try {
      await _api().meshUpload([for (final m in waiting) m.toJson()]);
      _uploaded.addAll(waiting.map((m) => m.msgId));
      final ids = messages.map((m) => m.msgId).toSet();
      _uploaded.retainAll(ids); // forget ids of messages we no longer keep
      await _prefs.setStringList('mesh_uploaded', _uploaded.toList());
      notifyListeners();
      return true;
    } catch (_) {
      return false; // no internet yet: try again later
    } finally {
      _uploading = false;
    }
  }

  Map<String, String> _readMap(String key) {
    try {
      final decoded = jsonDecode(_prefs.getString(key) ?? '{}') as Map;
      return {for (final e in decoded.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }
}
