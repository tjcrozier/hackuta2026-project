import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../theme.dart';

/// The red emergency button. It must be HELD for 2 seconds; a tap does nothing.
/// A ring fills while holding. Letting go early cancels.
class HoldButton extends StatefulWidget {
  const HoldButton({super.key, required this.label, required this.onHeld, this.busy = false});

  final String label;
  final VoidCallback onHeld;
  final bool busy;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Config.holdToStartMs),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onHeld();
        _hold.reset();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.busy) return;
    HapticFeedback.selectionClick();
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.status != AnimationStatus.completed) _hold.reset();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${widget.label}. Hold for 2 seconds.',
        child: Listener(
          onPointerDown: (_) => _down(),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => Container(
              height: 84,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: BB.danger,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: widget.busy ? null : _hold.value,
                          strokeWidth: 5,
                          color: BB.white,
                          backgroundColor: BB.white.withValues(alpha: 0.3),
                        ),
                        const Icon(Icons.warning_amber_outlined, color: BB.white, size: 26),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label, style: heading(20, color: BB.white)),
                        const SizedBox(height: 4),
                        Text(_hold.isAnimating ? 'Keep holding...' : 'Hold for 2 seconds',
                            style: body(14, color: BB.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
