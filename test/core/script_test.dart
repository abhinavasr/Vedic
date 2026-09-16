import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/translation.dart';
import 'package:vedic/core/script.dart';

void main() {
  test('tells the Indic scripts apart', () {
    const samples = {
      Script.devanagari: 'कर्मण्येवाधिकारस्ते',
      Script.bengali: 'সঞ্জয় বলিলেন',
      Script.gurmukhi: 'ਸੰਜੇ ਨੇ ਕਿਹਾ',
      Script.gujarati: 'સંજય બોલ્યા',
      Script.odia: 'ସଞ୍ଜୟ କହିଲେ',
      Script.tamil: 'சஞ்சயன் கூறினான்',
      Script.telugu: 'సంజయుడు చెప్పెను',
      Script.kannada: 'ಸಂಜಯ ಹೇಳಿದನು',
      Script.malayalam: 'സഞ്ജയൻ പറഞ്ഞു',
      Script.latin: 'Sanjaya said',
    };
    samples.forEach((script, text) {
      expect(dominantScript(text), script, reason: text);
      expect(isInScript(text, script), isTrue, reason: text);
    });
  });

  test('the danda and digits belong to no script', () {
    // Shared by every Indic script, so they cannot identify one.
    expect(dominantScript('॥ ।'), isNull);
    expect(countScripts('१२३ ०').values.every((n) => n == 0), isTrue);
  });

  test('an answer in a neighbouring script is caught', () {
    // The failure this guard exists for: asked for one language, a model
    // answers in another that looks similar.
    expect(isInScript('সঞ্জয় বলিলেন', Script.devanagari), isFalse);
    expect(isInScript('ಸಂಜಯ ಹೇಳಿದನು', Script.telugu), isFalse);
  });

  test('every offered language has a script the app can verify', () {
    for (final language in TargetLanguage.all) {
      expect(
        Script.values,
        contains(language.script),
        reason: '${language.name} would be unverifiable',
      );
      expect(language.endonym, isNotEmpty);
      expect(language.code, isNotEmpty);
    }
    // Codes are what a stored translation is keyed by, so they must be unique.
    final codes = TargetLanguage.all.map((l) => l.code).toSet();
    expect(codes, hasLength(TargetLanguage.all.length));
  });

  test('each endonym is written in its own script', () {
    for (final language in TargetLanguage.all) {
      expect(
        isInScript(language.endonym, language.script, minShare: 0.6),
        isTrue,
        reason: '${language.name}: ${language.endonym}',
      );
    }
  });
}
