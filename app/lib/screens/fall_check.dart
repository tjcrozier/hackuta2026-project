import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/shift.dart';
import '../theme.dart';

/// Full-screen "Did you fall?" / "Are you OK?" with a countdown and a huge "I'm OK" button.
/// If nobody answers before the countdown ends, the supervisor is alerted.
class FallCheck extends StatefulWidget {
  const FallCheck({super.key});

  @override
  State<FallCheck> createState() => _FallCheckState();
}

class _FallCheckState extends State<FallCheck> {
  Timer? _tick;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    // Every second: redraw the countdown and vibrate.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.vibrate();
      if (mounted) setState(() {});
    });
    HapticFeedback.vibrate();
    _startSound();
  }

  Future<void> _startSound() async {
    if (!Config.featureAlarmSound) return;
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('alarm.wav'));
    } catch (_) {
      // No sound is fine; the screen and the vibration still work.
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<Shift>();
    final check = shift.check;
    if (check == null) return const SizedBox.shrink();

    final secondsLeft = check.deadline.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final question = check.kind == CheckKind.fall ? 'Did you fall?' : 'Are you OK?';
    final reason = check.kind == CheckKind.fall
        ? 'Your phone felt a fall.'
        : 'Your phone has not moved for a while.';

    return Material(
      color: BB.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.report_problem_outlined, color: BB.help, size: 56),
              const SizedBox(height: 12),
              Text(question, textAlign: TextAlign.center, style: heading(44, color: BB.white)),
              const SizedBox(height: 8),
              Text(reason, textAlign: TextAlign.center, style: body(18, color: BB.line)),
              Expanded(
                child: Center(
                  child: check.alerted
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sms_outlined, color: BB.help, size: 48),
                            const SizedBox(height: 12),
                            Text('Your supervisor\nwas alerted',
                                textAlign: TextAlign.center,
                                style: heading(30, color: BB.white)),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$secondsLeft', style: heading(140, color: BB.white)),
                            Text('seconds until your supervisor is alerted',
                                textAlign: TextAlign.center, style: body(16, color: BB.line)),
                          ],
                        ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 140,
                child: FilledButton(
                  onPressed: shift.answerOk,
                  style: FilledButton.styleFrom(
                    backgroundColor: BB.safe,
                    foregroundColor: BB.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 44),
                      const SizedBox(width: 14),
                      Text('I\'m OK', style: heading(44, color: BB.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
