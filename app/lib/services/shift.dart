import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../models/mesh_message.dart';
import '../models/snapshot.dart';
import 'api.dart';
import 'floor.dart';
import 'live_socket.dart';
import 'mesh.dart';
import 'motion.dart';
import 'nearby.dart';
import 'rescue_beacon.dart';
import 'zone_beacon.dart';

/// Why the "Are you OK?" screen is showing.
enum CheckKind { fall, noMove }

/// An open "Did you fall?" / "Are you OK?" question.
class SafetyCheck {
  SafetyCheck(this.kind, this.deadline);
  final CheckKind kind;
  final DateTime deadline; // when the supervisor gets alerted
  bool alerted = false;
}

/// The worker's shift: who they are, where they are, and the ping loop.
/// Tracking only happens between startShift() and endShift().
class Shift extends ChangeNotifier {
  Shift(this.prefs) : floor = FloorService(prefs) {
    floor.addListener(notifyListeners);
    mesh = Mesh(prefs, () => api)
      ..onMessage = _onMeshMessage
      ..addListener(notifyListeners);
    nearby.init();
  }

  /// Precise distance to another phone (Nearby Interaction). Screens listen to it directly.
  final nearby = Nearby();

  /// Phone-to-phone messages when the internet is down.
  late final Mesh mesh;

  final SharedPreferences prefs;
  final FloorService floor;

  LiveSocket? _socket;
  late final MotionService _motion = MotionService(onSignal: _onMotion);
  Timer? _checkTimer;

  /// Not null while the "Did you fall?" / "Are you OK?" screen must be shown.
  SafetyCheck? check;
  int _run = 0; // changes on every start/end so an old ping loop stops itself

  // ---- saved details ----
  String get serverUrl => prefs.getString('server_url') ?? _defaultServerUrl;

  /// When the web build is served by the server itself (at /app), the server is
  /// simply the address in the browser. Otherwise use the configured default.
  static String get _defaultServerUrl =>
      kIsWeb && Uri.base.path.startsWith('/app') ? Uri.base.origin : Config.defaultServerUrl;
  String? get workerId => prefs.getString('worker_id');
  String get name => prefs.getString('name') ?? '';
  bool get joined => workerId != null;
  Api get api => Api(serverUrl);

  Future<void> setServerUrl(String url) async {
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isNotEmpty && !clean.startsWith('http')) clean = 'http://$clean';
    await prefs.setString('server_url', clean.isEmpty ? Config.defaultServerUrl : clean);
    notifyListeners();
  }

  // ---- live state ----
  bool onShift = false;
  String? zone;
  bool zoneFromBeacon = false;
  int? battery;
  DateTime? lastPing; // last ping the server accepted
  bool online = false; // did the last ping reach the server?
  bool rescueActive = false;
  bool helpSent = false;
  Snapshot? snapshot;

  // ---- Rescue Mode answer ("I'm safe" / "I need help") ----
  String? _answer; // what the worker tapped during this rescue
  String? _unsentAnswer; // not yet accepted by the server; retried with every ping

  /// "none", "safe" or "help" for the current rescue.
  String get rescueStatus {
    if (_answer != null) return _answer!;
    for (final worker in snapshot?.workers ?? const <WorkerInfo>[]) {
      if (worker.id == workerId) return worker.status; // e.g. answered by text
    }
    return 'none';
  }

  bool get answerSent => _unsentAnswer == null;

  bool _serverRescue = false; // what the server says
  bool _localRescue = false; // started over the mesh while offline

  void _setRescue(bool serverActive) {
    _serverRescue = serverActive;
    _applyRescue();
  }

  void _applyRescue() {
    final active = _serverRescue || _localRescue;
    if (rescueActive && !active) {
      _answer = null; // the rescue ended: forget the answer
      _unsentAnswer = null;
    }
    rescueActive = active;
    _syncBeacon();
    _syncMesh();
  }

  // ---- offline mesh ----

  /// Manual "Offline mode" switch (for the demo, and for phones that are not on a shift).
  bool offlineMode = false;
  bool _pingFailed = false; // the last ping did not reach the server
  DateTime? _lastMeshPing;
  CollapseWatch? _collapseWatch;

  /// This phone's id on the mesh: the worker id, or a made-up one for rescuers.
  String get meshId {
    if (workerId != null) return workerId!;
    var id = prefs.getString('mesh_id');
    if (id == null) {
      id = 'r${1000 + Random().nextInt(9000)}';
      prefs.setString('mesh_id', id);
    }
    return id;
  }

  void setOfflineMode(bool on) {
    offlineMode = on;
    _syncMesh();
    notifyListeners();
  }

  /// The mesh runs in Offline mode, in Rescue Mode, and when pings stop getting through.
  void _syncMesh() {
    final wanted = offlineMode || (onShift && (rescueActive || _pingFailed));
    if (wanted && (!mesh.running || mesh.selfId != meshId)) {
      mesh.start(
        id: meshId,
        name: name.isEmpty ? 'Rescuer' : name,
        siteCode: prefs.getString('site_code') ?? Config.siteCode,
      );
    } else if (!wanted && mesh.running) {
      mesh.stop();
    }
  }

  /// Send a mesh message with this phone's last known spot.
  void sendMesh(String type, String body) =>
      mesh.send(type: type, body: body, zone: zone, floor: floor.floor, battery: battery);

  void _onMeshMessage(MeshMessage message) {
    if (message.type == 'ni_token') {
      nearby.handleToken(mesh, message); // a rescuer's phone wants to find this phone
      return;
    }
    if (!onShift) return;
    if (message.type == 'rescue' && !rescueActive) {
      _localRescue = true; // another phone started Rescue Mode offline
      _applyRescue();
      notifyListeners();
    } else if (message.type == 'shock') {
      _checkCollapse(message.originWorkerId);
    }
  }

  /// Offline rescue start: this phone's shock plus shocks from other phones.
  void _checkCollapse(String phoneId) {
    if (_collapseWatch?.selfId != meshId) _collapseWatch = CollapseWatch(meshId);
    final phones = _collapseWatch!.addShock(phoneId, DateTime.now().millisecondsSinceEpoch);
    if (phones == null || rescueActive || online) return; // online: the server decides
    _localRescue = true;
    _applyRescue();
    sendMesh('rescue', 'impact on $phones phones (offline)');
    notifyListeners();
  }

  /// True while this phone advertises so rescuers can find it.
  bool beaconOn = false;
  bool _beaconWanted = false;

  /// The beacon runs in Rescue Mode until the worker answers "safe".
  void _syncBeacon() {
    final wanted = Config.featureRescueBeacon &&
        onShift &&
        rescueActive &&
        workerId != null &&
        rescueStatus != 'safe';
    if (wanted == _beaconWanted) return;
    _beaconWanted = wanted;
    if (wanted) {
      RescueBeacon.start(workerId!).then((started) {
        beaconOn = started && _beaconWanted;
        notifyListeners();
      });
    } else {
      beaconOn = false;
      RescueBeacon.stop();
    }
  }

  Future<void> answerRescue(String status) async {
    _answer = status;
    _unsentAnswer = status;
    _syncBeacon();
    // Also send it over the mesh, in case the internet is down.
    sendMesh(status, status == 'safe' ? 'I\'m safe' : 'I need help');
    notifyListeners();
    await _flushAnswer();
  }

  Future<void> _flushAnswer() async {
    final status = _unsentAnswer;
    if (status == null || workerId == null) return;
    try {
      await api.checkin(workerId: workerId!, status: status);
      if (_unsentAnswer == status) _unsentAnswer = null;
    } catch (_) {
      // Stays unsent; the ping loop tries again.
    }
    notifyListeners();
  }

  /// Open hazards on the worker's floor.
  List<Hazard> get hazardsHere =>
      snapshot?.hazards.where((h) => h.open && h.floor == floor.floor).toList() ?? [];

  int get pingSeconds => rescueActive ? Config.pingRescueSec : Config.pingNormalSec;

  /// Join the site, save the details on this phone, and start the shift.
  Future<void> join({required String name, required String phone, required String siteCode}) async {
    final id = await api.join(name: name, phone: phone, siteCode: siteCode);
    await prefs.setString('worker_id', id);
    await prefs.setString('name', name);
    await prefs.setString('phone', phone);
    await prefs.setString('site_code', siteCode);
    startShift();
  }

  /// Start the shift again if the app was closed in the middle of one.
  /// Returns true when it did.
  bool resumeShift() {
    if (!joined || prefs.getBool('on_shift') != true) return false;
    startShift();
    return true;
  }

  void startShift() {
    if (onShift || !joined) return;
    onShift = true;
    prefs.setBool('on_shift', true);
    final run = ++_run;
    if (Config.featureKeepAwake) WakelockPlus.enable().catchError((_) {});
    floor.start();
    _motion.start();
    _socket = LiveSocket(
      baseUrl: serverUrl,
      onSnapshot: (s) {
        snapshot = s;
        mesh.learnNames({for (final w in s.workers) w.id: w.name});
        _setRescue(s.rescueActive);
        _syncBeacon(); // the answer may have changed (for example by text)
        notifyListeners();
      },
    )..connect();
    notifyListeners();
    _loop(run);
  }

  void endShift() {
    if (!onShift) return;
    onShift = false;
    prefs.setBool('on_shift', false);
    // Tell the server, so the dashboard stops showing this worker.
    if (workerId != null) api.endShift(workerId!).catchError((_) {});
    _run++;
    if (Config.featureKeepAwake) WakelockPlus.disable().catchError((_) {});
    floor.stop();
    _motion.stop();
    _checkTimer?.cancel();
    check = null;
    _socket?.close();
    _socket = null;
    helpSent = false;
    _localRescue = false;
    _pingFailed = false;
    _applyRescue();
    notifyListeners();
  }

  /// Fallback when no beacon is heard: the worker taps A, B or C.
  void pickZone(String newZone) {
    zone = newZone;
    zoneFromBeacon = false;
    notifyListeners();
    _pingOnce(scan: false);
  }

  /// "I need help" (true) and "I'm OK now" (false).
  Future<void> sendHelp(bool help) async {
    await api.checkin(workerId: workerId!, status: help ? 'help' : 'none');
    helpSent = help;
    notifyListeners();
  }

  // ---- motion safety ----

  void _onMotion(MotionSignal signal) {
    if (!onShift) return;
    switch (signal) {
      case MotionSignal.shock:
        _sendEvent('shock');
        sendMesh('shock', '');
        _checkCollapse(meshId);
      case MotionSignal.fall:
        if (check != null) return;
        _sendEvent('fall');
        _openCheck(CheckKind.fall);
      case MotionSignal.noMove:
        if (check == null) _openCheck(CheckKind.noMove);
    }
  }

  void _openCheck(CheckKind kind) {
    const wait = Duration(seconds: Config.fallAnswerSec);
    final opened = SafetyCheck(kind, DateTime.now().add(wait));
    check = opened;
    _checkTimer?.cancel();
    _checkTimer = Timer(wait, () {
      // No answer in time: alert the supervisor. The screen stays up.
      if (check != opened) return;
      opened.alerted = true;
      _sendEvent(kind == CheckKind.fall ? 'fall_alert' : 'no_move');
      notifyListeners();
    });
    notifyListeners();
  }

  /// The worker tapped "I'm OK".
  void answerOk() {
    final answered = check;
    if (answered == null) return;
    _checkTimer?.cancel();
    check = null;
    _motion.resetNoMove();
    // Tell the server when it already knows about a fall or an alert.
    if (answered.kind == CheckKind.fall || answered.alerted) _sendEvent('fall_ok');
    notifyListeners();
  }

  /// Sends an event. Tries a few times, because a lost fall alert is a big deal.
  Future<void> _sendEvent(String type) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _setRescue(await api.event(workerId: workerId!, type: type));
        notifyListeners();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _loop(int run) async {
    while (onShift && run == _run) {
      await _pingOnce(scan: true);
      if (!onShift || run != _run) return;
      await Future<void>.delayed(Duration(seconds: pingSeconds));
    }
  }

  Future<void> _pingOnce({required bool scan}) async {
    if (scan) {
      final found = await ZoneBeacon.scan();
      zoneFromBeacon = found != null;
      if (found != null) zone = found; // otherwise keep the last known / picked zone
    }
    battery = await _batteryLevel() ?? battery;
    final position = await _position();
    if (!onShift) return;

    // First hand over stored mesh messages (an offline "rescue" message makes the
    // server start Rescue Mode before we ask it below).
    final uploaded = await mesh.tryUpload();
    try {
      final serverRescue = await _sendPing(position);
      if (uploaded) _localRescue = false; // back online: the server decides from here
      _setRescue(serverRescue);
      online = true;
      _pingFailed = false;
      lastPing = DateTime.now();
    } on ApiException catch (error) {
      online = false;
      if (error.status == 404) {
        await _rejoin(position);
      } else {
        _pingFailed = true;
      }
    } catch (_) {
      online = false;
      _pingFailed = true;
    }
    if (_pingFailed) _meshPing();
    _syncMesh();
    await _flushAnswer();
    notifyListeners();
  }

  /// While offline, share this phone's spot over the mesh (at most every 30 seconds).
  void _meshPing() {
    final last = _lastMeshPing;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    _lastMeshPing = DateTime.now();
    sendMesh('ping', '');
  }

  Future<bool> _sendPing(Position? position) => api.ping(
        workerId: workerId!,
        zone: zone,
        floor: floor.floor,
        battery: battery,
        lat: position?.latitude,
        lng: position?.longitude,
        moving: _motion.moving,
      );

  /// The server forgot this worker (for example after a demo reset): join again quietly.
  Future<void> _rejoin(Position? position) async {
    try {
      final id = await api.join(
        name: name,
        phone: prefs.getString('phone') ?? '',
        siteCode: prefs.getString('site_code') ?? Config.siteCode,
      );
      await prefs.setString('worker_id', id);
      _setRescue(await _sendPing(position));
      online = true;
      lastPing = DateTime.now();
    } catch (_) {}
  }

  Future<int?> _batteryLevel() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null; // simulator or unsupported
    }
  }

  /// Location is only sent when the worker already allowed it. Never asks here.
  Future<Position?> _position() async {
    if (kIsWeb || !Config.featureLocation) return null;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return null;
      }
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}
