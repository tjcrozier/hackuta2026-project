import 'package:app/services/api.dart';
import 'package:app/services/athena.dart';
import 'package:app/widgets/athena_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(AthenaConversation chat) => MaterialApp(
        home: Scaffold(body: AthenaChat(conversation: chat, api: Api('http://localhost:1'))),
      );

  testWidgets('shows the intro and role questions when empty', (tester) async {
    await tester.pumpWidget(wrap(AthenaConversation('worker')));
    expect(find.textContaining('Never other workers'), findsOneWidget);
    expect(find.text('Any hazards on my floor?'), findsOneWidget);
    expect(find.text('Athena can be wrong. In an emergency, call 911.'), findsOneWidget);
  });

  testWidgets('shows both sides of the chat and marks offline replies', (tester) async {
    final chat = AthenaConversation('supervisor')
      ..turns.addAll(const [
        AthenaTurn(fromUser: true, text: 'Who is on Floor 3?'),
        AthenaTurn(fromUser: false, text: 'Ben needs help on Floor 3.'),
        AthenaTurn(fromUser: false, text: 'Athena is offline right now.', offline: true),
      ]);
    await tester.pumpWidget(wrap(chat));
    expect(find.text('Who is on Floor 3?'), findsOneWidget);
    expect(find.text('Ben needs help on Floor 3.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Who has low battery?'), findsOneWidget);
  });
}
