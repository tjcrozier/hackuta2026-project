import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder for a role that is built in a later phase.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('This screen is built in $phase.',
                textAlign: TextAlign.center, style: body(17, color: BB.muted)),
          ),
        ),
      );
}
