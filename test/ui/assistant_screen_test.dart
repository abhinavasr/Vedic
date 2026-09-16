import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/assistant.dart';
import 'package:vedic/ui/ai/assistant_screen.dart';

Future<Assistant> _pump(WidgetTester tester, AssistantState state) async {
  final assistant = Assistant()..state.value = state;
  await tester.pumpWidget(
    MaterialApp(home: AssistantScreen(assistant: assistant)),
  );
  await tester.pump();
  return assistant;
}

void main() {
  testWidgets('offers the download, with its size, when nothing is installed', (
    tester,
  ) async {
    await _pump(tester, const AssistantState(AssistantPhase.notInstalled));
    expect(find.byKey(const ValueKey('assistant-install')), findsOneWidget);
    expect(find.textContaining('2.4 GB'), findsWidgets);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
  });

  testWidgets('says why, and stays calm, when the phone cannot run it', (
    tester,
  ) async {
    await _pump(
      tester,
      const AssistantState(
        AssistantPhase.unsupported,
        message: 'This phone has 2 GB of memory; the assistant needs 3 GB.',
      ),
    );
    expect(find.textContaining('needs 3 GB'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-install')), findsNothing);
    expect(find.textContaining('Everything else in Sadhana works'), findsOne);
  });

  testWidgets('shows download progress', (tester) async {
    await _pump(
      tester,
      const AssistantState(AssistantPhase.downloading, percent: 42),
    );
    expect(find.textContaining('42%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(0.42, 0.001),
    );
  });

  testWidgets('offers to remove the model once it is ready', (tester) async {
    await _pump(tester, const AssistantState(AssistantPhase.ready));
    expect(find.byKey(const ValueKey('assistant-remove')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove the assistant?'), findsOneWidget);

    // Backing out changes nothing.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-remove')), findsOneWidget);
  });
}
