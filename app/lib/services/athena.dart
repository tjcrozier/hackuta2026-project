import 'package:flutter/foundation.dart';

import 'api.dart';

/// One message in an Athena chat.
class AthenaTurn {
  const AthenaTurn({
    required this.fromUser,
    required this.text,
    this.offline = false,
  });

  final bool fromUser;
  final String text;

  /// Athena could not answer (no connection, no key). Not sent back to the model.
  final bool offline;
}

/// The chat with Athena for one role. Kept while the app is open, so closing and
/// reopening the chat panel keeps the conversation.
class AthenaConversation extends ChangeNotifier {
  AthenaConversation(this.role);

  /// 'worker', 'supervisor' or 'rescuer'. Decides what Athena may know.
  final String role;
  final List<AthenaTurn> turns = [];
  bool thinking = false;

  static final _byRole = <String, AthenaConversation>{};
  static AthenaConversation forRole(String role) =>
      _byRole.putIfAbsent(role, () => AthenaConversation(role));

  /// Quick questions shown as buttons above the text box.
  List<String> get suggestions => switch (role) {
    'supervisor' => const [
      'Who needs help?',
      'Today\'s hazards',
      'Who has low battery?',
    ],
    'rescuer' => const [
      'Who is missing?',
      'Where were they last seen?',
      'Nearest stairs?',
    ],
    _ => const [
      'Any hazards on my floor?',
      'What should I wear here?',
      'How do I report a hazard?',
    ],
  };

  Future<void> ask(Api api, String text, {String? workerId}) async {
    final question = text.trim();
    if (question.isEmpty || thinking) return;
    turns.add(AthenaTurn(fromUser: true, text: question));
    thinking = true;
    notifyListeners();
    try {
      final answer = await api.athena(
        role: role,
        workerId: workerId,
        messages: [
          for (final turn in turns)
            if (!turn.offline)
              {'role': turn.fromUser ? 'user' : 'assistant', 'text': turn.text},
        ],
      );
      turns.add(
        AthenaTurn(
          fromUser: false,
          text: answer.reply,
          offline: answer.source != 'groq',
        ),
      );
    } on ApiException catch (error) {
      turns.add(
        AthenaTurn(fromUser: false, text: error.message, offline: true),
      );
    } finally {
      thinking = false;
      notifyListeners();
    }
  }
}
