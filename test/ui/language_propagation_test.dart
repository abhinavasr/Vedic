import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the app's one reading language is allowed to be named directly.
///
/// Everywhere else goes through [ReadingLanguageScope], which registers the
/// screen so a change anywhere reaches it. Reading the singleton instead
/// compiles, looks right, and quietly shows whatever was true when the widget
/// was first drawn — which is how the Profile row went on saying "Hindi"
/// after the language had been changed to something else.
const _mayNameTheSingleton = {
  // Creates it.
  'lib/main.dart',
  // Declares it.
  'lib/ai/reading_languages.dart',
  // Puts it into the scope, above everything else.
  'lib/ui/app.dart',
};

void main() {
  test('screens take the reading language from the scope, not the singleton', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (_mayNameTheSingleton.contains(path)) continue;
      if (file.readAsStringSync().contains('ReadingLanguage.instance')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use ReadingLanguageScope.of(context) so the screen rebuilds when '
          'the language changes.',
    );
  });
}
