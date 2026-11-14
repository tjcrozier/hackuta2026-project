import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The two files a finished LiDAR scan produces.
class ScanFiles {
  ScanFiles({required this.modelPath, required this.jsonPath});
  final String modelPath; // .usdz 3D model
  final String jsonPath; // RoomPlan JSON (walls, doors, windows, openings, objects)
}

/// Bridge to Apple RoomPlan (ios/Runner/RoomScanViewController.swift).
class RoomPlan {
  static const _channel = MethodChannel('blackbox/roomplan');

  /// True only on iPhones and iPads with LiDAR.
  static Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the native scanner. Returns null if the supervisor cancelled.
  /// Throws a PlatformException if the scan failed.
  static Future<ScanFiles?> startScan() async {
    final files = await _channel.invokeMapMethod<String, String>('startScan');
    final model = files?['model'];
    final json = files?['json'];
    if (model == null || json == null) return null;
    return ScanFiles(modelPath: model, jsonPath: json);
  }
}
