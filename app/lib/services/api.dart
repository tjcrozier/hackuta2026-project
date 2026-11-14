import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/snapshot.dart';
import 'snapshot_cache.dart';

/// The server answered with an error, or could not be reached (status 0).
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Calls the Black Box server (see BUILD_PLAN.md, "REST API").
class Api {
  Api(this.baseUrl);
  final String baseUrl;

  static const _timeout = Duration(seconds: 6);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl$path'),
              headers: {'content-type': 'application/json'}, body: jsonEncode(data))
          .timeout(_timeout);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'No connection to the server. Try again in a moment.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400) {
      final detail = map['detail'];
      throw ApiException(
          response.statusCode, detail is String ? detail : 'Server error ${response.statusCode}.');
    }
    return map;
  }

  /// Returns the new worker id.
  Future<String> join({required String name, required String phone, required String siteCode}) async {
    final reply = await _post('/workers/join', {'name': name, 'phone': phone, 'site_code': siteCode});
    return reply['worker_id'] as String;
  }

  /// Sends one ping. Returns true when Rescue Mode is active.
  Future<bool> ping({
    required String workerId,
    String? zone,
    int? floor,
    int? battery,
    double? lat,
    double? lng,
    bool moving = true,
    String source = 'internet',
  }) async {
    final reply = await _post('/ping', {
      'worker_id': workerId,
      'zone': zone,
      'floor': floor,
      'battery': battery,
      'lat': lat,
      'lng': lng,
      'moving': moving,
      'source': source,
    });
    return reply['rescue_active'] == true;
  }

  /// End shift: the worker disappears from the dashboard until their next ping.
  Future<void> endShift(String workerId) => _post('/workers/$workerId/end_shift', {});

  /// type: shock, fall, fall_ok, fall_alert, no_move. Returns true when Rescue Mode is active.
  Future<bool> event({required String workerId, required String type}) async {
    final reply = await _post('/event', {'worker_id': workerId, 'type': type});
    return reply['rescue_active'] == true;
  }

  /// status: none, safe, help.
  Future<void> checkin({required String workerId, required String status, String? note}) async {
    await _post('/checkin', {'worker_id': workerId, 'status': status, 'note': note});
  }

  Future<void> rescueStart(String reason) => _post('/rescue/start', {'reason': reason});

  Future<void> rescueStop() => _post('/rescue/stop', {});

  /// Uploads a floor scan. The server compares it with the floor's last scan.
  Future<ScanResult> uploadScan({
    required int floor,
    required List<int> model,
    required List<int> roomJson,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scan'))
        ..fields['floor'] = '$floor'
        ..files.add(http.MultipartFile.fromBytes('model', model, filename: 'room.usdz'))
        ..files.add(http.MultipartFile.fromBytes('room_json', roomJson, filename: 'room.json'));
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      return ScanResult.fromJson(_decode(await http.Response.fromStream(streamed)));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'No connection to the server. Try again in a moment.');
    }
  }

  /// status: open, fixed, false_alarm.
  Future<void> setHazardStatus(int hazardId, String status) =>
      _post('/hazards/$hazardId', {'status': status});

  /// Texts the workers on the hazard's floor. Returns how many were warned.
  Future<int> warnFloor(int hazardId) async {
    final reply = await _post('/hazards/$hazardId/warn', {});
    return (reply['sent'] as num?)?.toInt() ?? 0;
  }

  /// Hands mesh messages to the server. The server ignores ones it already has.
  Future<void> meshUpload(List<Map<String, dynamic>> messages) =>
      _post('/mesh/upload', {'messages': messages});

  /// Demo mode only: back to the 14 demo workers and yesterday's scans.
  Future<void> demoReset() => _post('/demo/reset', {});

  Future<Snapshot> state() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/state')).timeout(_timeout);
      final json = _decode(response);
      SnapshotCache.save(json);
      return Snapshot.fromJson(json);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'No connection to the server. Try again in a moment.');
    }
  }
}
