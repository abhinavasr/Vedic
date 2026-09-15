import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/output_hygiene.dart';
import 'package:vedic/core/script.dart';

void main() {
  group('cleanOutput', () {
    test('removes leaked control tokens', () {
      expect(cleanOutput('Hello.<end_of_turn>'), 'Hello.');
      expect(cleanOutput('<start_of_turn>Hi<eos>'), 'Hi');
    });

    test('normalises line endings and collapses blank lines', () {
      expect(cleanOutput('a\r\nb'), 'a\nb');
      expect(cleanOutput('a\n\n\n\nb'), 'a\n\nb');
      expect(cleanOutput('  padded \n'), 'padded');
    });
  });

  group('detectRunaway', () {
    test('leaves healthy text alone', () {
      expect(detectRunaway('A perfectly normal answer [1].'), isNull);
      expect(detectRunaway('Om namah shivaya. ' * 3), isNull);
    });

    test('catches one character repeated forever and keeps one copy', () {
      const prefix = 'The answer is ';
      final text = prefix + 'ा' * 50;
      expect(detectRunaway(text), prefix.length + 1);
    });

    test('catches a looping phrase and keeps one copy', () {
      const prefix = 'Here it is. ';
      final text = prefix + 'I am. ' * 30;
      expect(detectRunaway(text), prefix.length + 'I am. '.length);
    });

    test('caps overall length', () {
      expect(detectRunaway('abcdefghij', maxChars: 5), 5);
    });
  });

  group('script', () {
    test('identifies the dominant script', () {
      expect(dominantScript('धर्मक्षेत्रे कुरुक्षेत्रे'), Script.devanagari);
      expect(dominantScript('ಧರ್ಮಕ್ಷೇತ್ರೇ'), Script.kannada);
      expect(dominantScript('dharmakṣetre kurukṣetre'), Script.latin);
      expect(dominantScript('123 ।'), isNull);
    });

    test('checks an answer is mostly in the expected script', () {
      expect(
        isInScript('Answer in English with one word धर्म', Script.latin),
        isTrue,
      );
      expect(isInScript('धर्मक्षेत्रे कुरुक्षेत्रे', Script.latin), isFalse);
      expect(isInScript('', Script.kannada), isTrue);
    });
  });
}
