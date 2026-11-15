import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';

/// The Cycl0ps logo: one eye, like the Cyclops. Long-press it to open the hidden demo tools.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          context.push('/demo');
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: BB.ink, borderRadius: BorderRadius.circular(size / 4)),
          child: Icon(Icons.adjust, color: BB.white, size: size * 0.6),
        ),
      );
}
