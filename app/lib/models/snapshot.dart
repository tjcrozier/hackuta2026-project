/// The server snapshot (GET /state and WS /live). Only the parts the app uses.
class Snapshot {
  Snapshot({
    required this.siteName,
    required this.rescueActive,
    required this.rescueReason,
    required this.workers,
    required this.hazards,
    this.rescueStartedAt,
    this.scans = const {},
  });

  final String siteName;
  final bool rescueActive;
  final String? rescueReason;
  final List<WorkerInfo> workers;
  final List<Hazard> hazards;
  final int? rescueStartedAt; // seconds since 1970
  final Map<int, ScanInfo> scans; // newest scan per floor

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    final rescue = (json['rescue'] as Map?) ?? const {};
    return Snapshot(
      siteName: ((json['site'] as Map?)?['name'] as String?) ?? '',
      rescueActive: rescue['active'] == true,
      rescueReason: rescue['reason'] as String?,
      workers: ((json['workers'] as List?) ?? const [])
          .map((w) => WorkerInfo.fromJson(Map<String, dynamic>.from(w as Map)))
          .toList(),
      hazards: ((json['hazards'] as List?) ?? const [])
          .map((h) => Hazard.fromJson(Map<String, dynamic>.from(h as Map)))
          .toList(),
      rescueStartedAt: (rescue['started_at'] as num?)?.toInt(),
      scans: {
        for (final entry in ((json['scans'] as Map?) ?? const {}).entries)
          if (int.tryParse('${entry.key}') != null)
            int.parse('${entry.key}'):
                ScanInfo.fromJson(Map<String, dynamic>.from(entry.value as Map)),
      },
    );
  }
}

/// The newest scan of one floor.
class ScanInfo {
  ScanInfo({required this.ts, required this.parts, this.model});

  final int ts; // seconds since 1970
  final Map<String, int> parts; // walls, doors, windows, openings
  final String? model;

  factory ScanInfo.fromJson(Map<String, dynamic> json) => ScanInfo(
        ts: (json['ts'] as num?)?.toInt() ?? 0,
        model: json['model'] as String?,
        parts: {
          for (final entry in ((json['parts'] as Map?) ?? const {}).entries)
            '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
        },
      );
}

class WorkerInfo {
  WorkerInfo({
    required this.id,
    required this.name,
    this.zone,
    this.floor,
    this.battery,
    this.lastPing,
    this.moving = false,
    this.source,
    this.status = 'none',
    this.phoneLost = false,
  });

  final String id;
  final String name;
  final String? zone;
  final int? floor;
  final int? battery;
  final int? lastPing; // seconds since 1970
  final bool moving;
  final String? source; // "internet" or "mesh"
  final String status; // "none", "safe" or "help"
  final bool phoneLost;

  factory WorkerInfo.fromJson(Map<String, dynamic> json) => WorkerInfo(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        zone: json['zone'] as String?,
        floor: (json['floor'] as num?)?.toInt(),
        battery: (json['battery'] as num?)?.toInt(),
        lastPing: (json['last_ping'] as num?)?.toInt(),
        moving: json['moving'] == true,
        source: json['source'] as String?,
        status: (json['status'] as String?) ?? 'none',
        phoneLost: json['phone_lost'] == true,
      );
}

class Hazard {
  Hazard({
    required this.id,
    required this.floor,
    required this.text,
    required this.oshaTopic,
    required this.status,
    this.before,
    this.after,
  });

  final int id;
  final int floor;
  final String text;
  final String oshaTopic;
  final String status; // "open", "fixed" or "false_alarm"
  final Map<String, int>? before; // part counts in the scan before
  final Map<String, int>? after; // part counts in the scan that found the hazard

  bool get open => status == 'open';

  factory Hazard.fromJson(Map<String, dynamic> json) => Hazard(
        id: (json['id'] as num).toInt(),
        floor: (json['floor'] as num?)?.toInt() ?? 0,
        text: (json['text'] as String?) ?? '',
        oshaTopic: (json['osha_topic'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'open',
        before: _counts(json['before']),
        after: _counts(json['after']),
      );

  static Map<String, int>? _counts(Object? value) => value is Map
      ? {for (final e in value.entries) '${e.key}': (e.value as num?)?.toInt() ?? 0}
      : null;
}

/// What the server answers after a scan upload.
class ScanResult {
  ScanResult({required this.scanId, required this.parts, required this.hazards});

  final int scanId;
  final Map<String, int> parts;
  final List<Hazard> hazards; // new hazards found by this scan

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        scanId: (json['scan_id'] as num?)?.toInt() ?? 0,
        parts: Hazard._counts(json['parts']) ?? const {},
        hazards: ((json['hazards'] as List?) ?? const [])
            .map((h) => Hazard.fromJson(Map<String, dynamic>.from(h as Map)))
            .toList(),
      );
}
