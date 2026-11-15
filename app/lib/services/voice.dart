import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Athena's voice: Apple's built-in text-to-speech (VoiceService in
/// ios/Runner/AppDelegate.swift). Speaks on the phone; no audio leaves it.
/// On the web, or if the bridge is missing, it stays quiet and captions still work.
class Voice {
  static const _methods = MethodChannel('blackbox/voice');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Speaks [text]. Finishes when Athena is done talking (true) or was cut off (false).
  static Future<bool> speak(String text) async {
    if (!available || text.trim().isEmpty) return false;
    try {
      return await _methods.invokeMethod<bool>('speak', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!available) return;
    try {
      await _methods.invokeMethod<void>('stop');
    } catch (_) {
      // Nothing to stop.
    }
  }
}
