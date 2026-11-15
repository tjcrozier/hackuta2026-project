import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/athena.dart';
import '../theme.dart';
import 'athena_chat.dart';

/// Adds Athena to a web page (dashboard, rescuer page).
/// Wide screens: a chat panel on the right. Narrow screens: an "Ask Athena" button
/// that opens the chat as a sheet from the bottom.
class AthenaDock extends StatelessWidget {
  const AthenaDock({
    super.key,
    required this.child,
    required this.api,
    required this.role,
  });

  final Widget child;
  final Api api;
  final String role;

  @override
  Widget build(BuildContext context) {
    if (!Config.featureAthena) return child;
    final conversation = AthenaConversation.forRole(role);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 1200) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              Container(
                width: 380,
                decoration: const BoxDecoration(
                  color: BB.ground,
                  border: Border(left: BorderSide(color: BB.line)),
                ),
                child: AthenaChat(
                  conversation: conversation,
                  api: api,
                  header: true,
                ),
              ),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              right: 16,
              bottom: 16,
              child: FilledButton.icon(
                onPressed: () => _openSheet(context, conversation),
                style: FilledButton.styleFrom(
                  backgroundColor: BB.ink,
                  foregroundColor: BB.white,
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                icon: const Icon(athenaIcon),
                label: Text(
                  'Ask Athena',
                  style: body(16, color: BB.white, weight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openSheet(BuildContext context, AthenaConversation conversation) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BB.ground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheet).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.85,
            child: AthenaChat(
              conversation: conversation,
              api: api,
              header: true,
              onClose: () => Navigator.of(sheet).pop(),
            ),
          ),
        ),
      );
}
