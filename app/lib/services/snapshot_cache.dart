import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/snapshot.dart';

/// Keeps the last server snapshot on the phone, so screens can still show the last
/// known crew, hazards and scans when the internet drops.
class SnapshotCache {
  static const _key = 'last_snapshot';
  static const _timeKey = 'last_snapshot_at';

  /// When the saved snapshot arrived (null if none).
  static DateTime? savedAt;

  static Future<void> save(Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(_key, jsonEncode(json));
      await prefs.setInt(_timeKey, now.millisecondsSinceEpoch);
      savedAt = now;
    } catch (_) {}
  }

  static Future<Snapshot?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final at = prefs.getInt(_timeKey);
      savedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
      return Snapshot.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}
