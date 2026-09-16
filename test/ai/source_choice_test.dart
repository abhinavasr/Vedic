import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/translation.dart';
import 'package:vedic/core/script.dart';

const _sanskrit = 'दृष्ट्वा तु पाण्डवानीकं व्यूढं दुर्योधनस्तदा ।';

void main() {
  test('the Sanskrit is the last resort, not the first choice', () {
    // Measured on a phone: this model misreads ordinary Sanskrit words, and
    // going from a rendering someone already made is a far easier task.
    final source = chooseSource(
      target: TargetLanguage.hindi,
      original: _sanskrit,
      available: const {'en': 'Duryodhana went to his teacher.'},
    );
    expect(source.languageCode, 'en');
    expect(source.languageName, 'English');
    expect(source.isOriginal, isFalse);
  });

  test('falls back to the original when nothing else exists', () {
    final source = chooseSource(
      target: TargetLanguage.english,
      original: _sanskrit,
    );
    expect(source.languageCode, 'sa');
    expect(source.languageName, 'Sanskrit');
    expect(source.text, _sanskrit);
    expect(source.isOriginal, isTrue);
  });

  test('an Indic target prefers Hindi, others prefer English', () {
    const both = {'en': 'In English.', 'hi': 'हिन्दी में।'};

    // Marathi shares Hindi's script and most of its vocabulary, so less is
    // lost on the way.
    expect(
      chooseSource(
        target: const TargetLanguage(
          code: 'mr',
          name: 'Marathi',
          endonym: 'मराठी',
          script: Script.devanagari,
          scriptName: 'Devanagari',
        ),
        original: _sanskrit,
        available: both,
      ).languageCode,
      'hi',
    );

    expect(
      chooseSource(
        target: TargetLanguage.english,
        original: _sanskrit,
        available: both,
      ).languageCode,
      'hi',
      reason: 'English is the target, so Hindi is what is left to work from',
    );
  });

  test('never translates a language out of itself', () {
    final source = chooseSource(
      target: TargetLanguage.hindi,
      original: _sanskrit,
      available: const {'hi': 'हिन्दी में।'},
    );
    expect(source.isOriginal, isTrue);
  });

  test('ignores an empty rendering', () {
    final source = chooseSource(
      target: TargetLanguage.hindi,
      original: _sanskrit,
      available: const {'en': '   '},
    );
    expect(source.isOriginal, isTrue);
  });
}
