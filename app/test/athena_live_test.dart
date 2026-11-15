import 'package:app/screens/athena_live_screen.dart';
import 'package:app/services/api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('looks like a call: quick questions, ask box and End stay on screen',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS; // voice buttons are iPhone-only
    await tester.pumpWidget(
      MaterialApp(home: AthenaLiveScreen(api: Api('http://localhost:1'))),
    );
    await tester.pump();

    expect(find.text('Athena'), findsOneWidget);
    for (final question in AthenaLiveScreen.quickQuestions) {
      expect(find.text(question), findsOneWidget);
    }
    expect(find.text('Ask about what you see'), findsOneWidget);
    expect(find.byTooltip('End'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Replay'), findsOneWidget);

    // Mute works even before the first answer, and shows its state in words.
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(find.text('Unmute'), findsOneWidget);
    // No camera in tests: the quick questions wait for it instead of crashing.
    final drink = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Can I drink it?'), matching: find.byType(FilledButton)),
    );
    expect(drink.onPressed, isNull);

    await tester.pumpWidget(const SizedBox()); // ends the call and stops its clock
    debugDefaultTargetPlatformOverride = null;
  });
}
