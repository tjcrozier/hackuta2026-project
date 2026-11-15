import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/athena.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/athena_chat.dart';

/// Athena full screen on a phone. role is 'worker' or 'supervisor'.
class AthenaScreen extends StatelessWidget {
  const AthenaScreen({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final shift = context.read<Shift>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(athenaIcon, size: 22),
            const SizedBox(width: 10),
            Text('Athena', style: heading(20)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: AthenaChat(
          conversation: AthenaConversation.forRole(role),
          api: shift.api,
          workerId: role == 'worker' ? shift.workerId : null,
        ),
      ),
    );
  }
}
