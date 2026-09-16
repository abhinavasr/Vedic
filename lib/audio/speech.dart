import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../ai/translation.dart';

// Reading a verse's meaning aloud with the phone's own voice.
//
// The verse itself is not read this way. Sounding the Sanskrit out from its
// transliteration was tried on a phone and was not worth offering: an English
// voice does nothing good with romanised Sanskrit. A chant has to be a
// recording by someone who knows the text, so until a pack carries one there
// is no chant — only the meaning, which a phone reads perfectly well.

/// Where each language's voice is usually found. The phone matches on the
/// whole tag, so a bare "hi" finds nothing on most devices.
const Map<String, String> _locales = {
  'en': 'en-IN',
  'hi': 'hi-IN',
  'mr': 'mr-IN',
  'ne': 'ne-NP',
  'gu': 'gu-IN',
  'bn': 'bn-IN',
  'pa': 'pa-IN',
  'or': 'or-IN',
  'ta': 'ta-IN',
  'te': 'te-IN',
  'kn': 'kn-IN',
  'ml': 'ml-IN',
  'es': 'es-ES',
  'fr': 'fr-FR',
  'de': 'de-DE',
  'pt': 'pt-BR',
  'id': 'id-ID',
};

/// What the phone will actually read, and in which voice.
@immutable
class SpokenChoice {
  const SpokenChoice({
    required this.text,
    required this.locale,
    required this.languageCode,
    required this.description,
  });

  final String text;

  /// BCP 47, so a caller can match other text to the same voice.
  final String languageCode;

  /// The tag handed to the platform, e.g. "hi-IN".
  final String locale;

  /// What to tell the reader is about to happen, since none of this is a
  /// chant and the difference matters.
  final String description;
}

/// The platform's voice, behind a seam so the logic above it can be tested
/// without a phone.
abstract class SpeechEngine {
  Future<List<Object?>> languages();

  /// Makes [speak] return when the voice has finished rather than when it
  /// starts.
  Future<void> awaitCompletion();

  Future<void> configure({required String locale, required double rate});

  Future<void> speak(String text);

  Future<void> stop();
}

class PlatformSpeech implements SpeechEngine {
  PlatformSpeech({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<List<Object?>> languages() async =>
      await _tts.getLanguages as List<Object?>;

  @override
  Future<void> awaitCompletion() => _tts.awaitSpeakCompletion(true);

  @override
  Future<void> configure({required String locale, required double rate}) async {
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(1);
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

class VerseSpeech {
  VerseSpeech({SpeechEngine? engine}) : _tts = engine ?? PlatformSpeech();

  /// The app's. Replaceable in tests.
  static VerseSpeech instance = VerseSpeech();

  final SpeechEngine _tts;

  /// The passage being read aloud, so one verse's control shows as playing
  /// and the others do not.
  final speaking = ValueNotifier<String?>(null);

  var _wired = false;
  Set<String>? _available;

  /// Bumped by every stop and every new utterance, so a finished `speak` can
  /// tell whether it ran to the end or was cut off.
  var _token = 0;

  /// Which languages this phone can actually speak. Empty when the platform
  /// will not say, in which case every language is attempted.
  Future<Set<String>> availableLocales() async {
    if (_available case final known?) return known;
    try {
      final languages = await _tts.languages();
      return _available = {
        for (final language in languages) '$language'.toLowerCase(),
      };
    } on Object {
      // A phone that will not list its voices may still have one.
      return _available = const {};
    }
  }

  Future<bool> _speakable(String code) async {
    final locale = _locales[code];
    if (locale == null) return false;
    final voices = await availableLocales();
    // A phone that will not list its voices may still have one.
    if (voices.isEmpty) return true;
    return voices.contains(locale.toLowerCase()) ||
        voices.any((v) => v.startsWith('$code-') || v == code);
  }

  /// How to read a translation aloud, in the reader's language where the
  /// phone has that voice and English otherwise.
  ///
  /// [available] maps a language code to the text in that language.
  Future<SpokenChoice?> chooseForMeaning({
    required Map<String, String> available,
    required String preferred,
  }) async {
    for (final code in [preferred, 'en', ...available.keys]) {
      final text = available[code];
      if (text == null || text.trim().isEmpty) continue;
      if (!await _speakable(code)) continue;
      return SpokenChoice(
        text: text,
        locale: _locales[code]!,
        languageCode: code,
        description: 'Read aloud in ${languageName(code)}',
      );
    }
    return null;
  }

  /// Reads [choice] aloud, and stops anything already being read.
  /// Reads [choice] aloud and returns when the voice has finished.
  ///
  /// False means it was cut off — stopped by the reader, or replaced by
  /// another utterance. A caller reading straight through must not treat that
  /// as "this verse is done" and turn the page.
  Future<bool> speak(String ref, SpokenChoice choice) async {
    await stop();
    await _wire();
    final token = ++_token;
    try {
      // Scripture read at conversational speed runs away from the reader.
      await _tts.configure(locale: choice.locale, rate: 0.42);
      speaking.value = ref;
      await _tts.speak(choice.text);
    } on Object {
      if (token == _token) speaking.value = null;
      rethrow;
    }
    if (token != _token) return false;
    speaking.value = null;
    return true;
  }

  Future<void> stop() async {
    // Before the await: anything in flight is now cut off, whoever is asking.
    _token++;
    speaking.value = null;
    try {
      await _tts.stop();
    } on Object {
      // Nothing was playing, or the platform has no opinion. Either is fine.
    }
  }

  Future<void> _wire() async {
    if (_wired) return;
    _wired = true;
    // Makes speak() finish when the voice does, which is what lets one verse
    // hand over to the next.
    await _tts.awaitCompletion();
  }
}
