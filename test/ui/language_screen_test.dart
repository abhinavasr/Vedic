import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/assistant.dart';
import 'package:vedic/ai/reading_languages.dart';
import 'package:vedic/ai/translation.dart';
import 'package:vedic/ui/settings/language_screen.dart';

class _MemorySettings implements AssistantSettings {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String? value) =>
      value == null ? values.remove(key) : values[key] = value;
}

void main() {
  testWidgets('lists every language and remembers the choice', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = _MemorySettings();
    final reading = ReadingLanguage(settings);
    expect(reading.language.code, 'en', reason: 'English until asked');

    await tester.pumpWidget(
      MaterialApp(home: LanguageScreen(reading: reading)),
    );
    await tester.pumpAndSettle();

    for (final language in TargetLanguage.all) {
      expect(
        find.byKey(ValueKey('language-${language.code}')),
        findsOneWidget,
        reason: language.name,
      );
    }

    await tester.tap(find.byKey(const ValueKey('language-ta')));
    await tester.pumpAndSettle();
    expect(reading.language.code, 'ta');
    expect(settings.values['reading.language'], 'ta');

    // A later run opens in the language that was chosen.
    expect(ReadingLanguage(settings).language.name, 'Tamil');
  });

  test('the reader\'s language leads, with the common two behind it', () {
    final settings = _MemorySettings()..values['reading.language'] = 'mr';
    expect(ReadingLanguage(settings).preference, ['mr', 'en', 'hi']);

    final english = _MemorySettings();
    expect(ReadingLanguage(english).preference, ['en', 'hi']);
  });
}
