import 'package:flutter/material.dart';

import '../theme.dart';

/// A tall, full-width button that is easy to hit with gloves.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = BB.accent,
    this.textColor = BB.white,
    this.height = 64,
    this.outlined = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final double height;
  final bool outlined;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final foreground = outlined ? BB.ink : textColor;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final child = busy
        ? SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3, color: foreground),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 26), const SizedBox(width: 10)],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: heading(height >= 64 ? 20 : 17, color: foreground)),
              ),
            ],
          );
    return SizedBox(
      width: double.infinity,
      height: height,
      child: outlined
          ? OutlinedButton(
              onPressed: busy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: const BorderSide(color: BB.ink, width: 1.5),
                shape: shape,
              ),
              child: child,
            )
          : FilledButton(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: foreground,
                disabledBackgroundColor: color.withValues(alpha: 0.5),
                disabledForegroundColor: foreground,
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}
