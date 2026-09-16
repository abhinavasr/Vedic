import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/assistant.dart';
import 'package:vedic/ai/model_host.dart';
import 'package:vedic/ui/ai/assistant_screen.dart';

class _MemorySettings implements AssistantSettings {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String? value) =>
      value == null ? values.remove(key) : values[key] = value;
}

/// A window tall enough that the whole screen is built, so a control that is
/// present is also findable.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<Assistant> _pump(WidgetTester tester, AssistantState state) async {
  _tallWindow(tester);
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

  testWidgets('offers a mirror, and remembers the choice', (tester) async {
    _tallWindow(tester);
    final settings = _MemorySettings();
    final assistant = Assistant(settings: settings)
      ..state.value = const AssistantState(AssistantPhase.notInstalled);
    await tester.pumpWidget(
      MaterialApp(home: AssistantScreen(assistant: assistant)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('host-mirror')));
    await tester.pumpAndSettle();
    expect(assistant.preferredHost, ModelHost.mirror);
    expect(settings.values['assistant.host'], 'mirror');

    // A later run starts from the saved choice.
    expect(Assistant(settings: settings).preferredHost, ModelHost.mirror);
  });

  testWidgets('a download can be stopped', (tester) async {
    await _pump(
      tester,
      const AssistantState(AssistantPhase.downloading, percent: 10),
    );
    expect(find.byKey(const ValueKey('assistant-cancel')), findsOneWidget);
  });

  testWidgets('says it is checking before any bytes move', (tester) async {
    await _pump(tester, const AssistantState(AssistantPhase.checking));
    expect(find.textContaining('Checking the download'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-install')), findsNothing);
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
