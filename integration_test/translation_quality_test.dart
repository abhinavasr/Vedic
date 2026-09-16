import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vedic/ai/assistant.dart';
import 'package:vedic/ai/translation.dart';

/// Measures what the installed model actually produces, on the device running
/// the test.
///
/// Run it against a device that already has the model installed:
///
/// ```sh
/// flutter test integration_test/translation_quality_test.dart -d <device> \
///   --dart-define=ASSISTANT_ALLOW_SIMULATOR=true
/// ```
///
/// The words it prints are the model's and are the same anywhere; the seconds
/// belong to whatever ran it. Read both, quote only the first.

// Bhagavad Gītā 1.2, with the pack's own renderings to translate from and to
// compare against.
const _sanskrit =
    'दृष्ट्वा तु पाण्डवानीकं व्यूढं दुर्योधनस्तदा ।\n'
    'आचार्यमुपसङ्गम्य राजा वचनमब्रवीत् ॥';

const _hindi =
    'संजय ने कहा: उस समय राजा दुर्योधन ने पाण्डवों की सेना को व्यूहरचना '
    'युक्त देखकर द्रोणाचार्य के पास जाकर यह वचन कहा।';

const _english =
    'Sanjaya said: O King, after looking over the army arranged in military '
    'formation by the sons of Pandu, King Duryodhana went to his teacher and '
    'spoke the following words.';

Future<void> _run(
  String label, {
  required String text,
  required String from,
  required TargetLanguage into,
  required String reference,
}) async {
  final started = DateTime.now();
  String? answer;
  String? rejected;
  try {
    answer = await translateVerse(
      Assistant.instance,
      verse: text,
      language: into,
      from: from,
    );
  } on TranslationRejected catch (e) {
    rejected = e.message;
  }
  final seconds = DateTime.now().difference(started).inSeconds;

  // ignore: avoid_print
  print('''

=== $label  ($seconds s)
FROM      : $text
REFERENCE : $reference
MODEL     : ${answer ?? 'REJECTED — $rejected'}
''');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Assistant.instance.refresh();
    await Assistant.instance.load();
    expect(
      Assistant.instance.state.value.canAnswer,
      isTrue,
      reason:
          'Install the model first by running the app on this device: '
          '${Assistant.instance.state.value.message ?? ''}',
    );
  });

  testWidgets('Sanskrit into English', (_) async {
    await _run(
      'sa -> en',
      text: _sanskrit,
      from: 'Sanskrit',
      into: TargetLanguage.english,
      reference: _english,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('Hindi into English', (_) async {
    await _run(
      'hi -> en',
      text: _hindi,
      from: 'Hindi',
      into: TargetLanguage.english,
      reference: _english,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('English into Hindi', (_) async {
    await _run(
      'en -> hi',
      text: _english,
      from: 'English',
      into: TargetLanguage.hindi,
      reference: _hindi,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('Sanskrit into Hindi', (_) async {
    await _run(
      'sa -> hi',
      text: _sanskrit,
      from: 'Sanskrit',
      into: TargetLanguage.hindi,
      reference: _hindi,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
