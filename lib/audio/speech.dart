import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../ai/translation.dart';
import '../core/transliteration.dart';

// Reading a verse aloud with the phone's own voice.
//
// This is the fallback for a verse whose pack carries no chant. A chant is a
// reading by someone who knows the text; this is a synthetic voice working
// from the letters. The two are never presented as the same thing.

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
    required this.description,
  });

  final String text;

  /// The tag handed to the platform, e.g. "hi-IN".
  final String locale;

  /// What to tell the reader is about to happen, since none of this is a
  /// chant and the difference matters.
  final String description;
}

class VerseSpeech {
  VerseSpeech({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  /// The app's. Replaceable in tests.
  static VerseSpeech instance = VerseSpeech();

  final FlutterTts _tts;

  /// The passage being read aloud, so one verse's control shows as playing
  /// and the others do not.
  final speaking = ValueNotifier<String?>(null);

  var _wired = false;
  Set<String>? _available;

  /// Which languages this phone can actually speak. Empty when the platform
  /// will not say, in which case every language is attempted.
  Future<Set<String>> availableLocales() async {
    if (_available case final known?) return known;
    try {
      final languages = await _tts.getLanguages as List<Object?>;
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

  /// How to sound out the verse itself: the phonetic, read by an English
  /// voice.
  ///
  /// The diacritics are folded away first — an English voice does nothing
  /// useful with ṛ or ṣ and mangles less without them. This is the verse's
  /// sound approximated by a phone, not a chant, and the control says so.
  Future<SpokenChoice?> chooseForChant({
    required String verse,
    String? transliteration,
  }) async {
    final phonetic = foldIast(transliteration ?? devanagariToIast(verse));
    if (phonetic.trim().isEmpty) return null;
    if (!await _speakable('en')) return null;
    return SpokenChoice(
      text: phonetic,
      locale: _locales['en']!,
      description: 'Sounded out from the phonetic — not a recorded chant',
    );
  }

  /// How to read a translation aloud, in the reader's language where the
  /// phone has that voice and English otherwise.
  ///
  /// Not wired to a control yet: the verse card offers the chant only. This
  /// is what listening to the meaning like an audiobook would use.
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
        description: 'Read aloud in ${languageName(code)}',
      );
    }
    return null;
  }

  /// Reads [choice] aloud, and stops anything already being read.
  Future<void> speak(String ref, SpokenChoice choice) async {
    await stop();
    _wire();
    try {
      await _tts.setLanguage(choice.locale);
      // Scripture read at conversational speed runs away from the reader.
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1);
      speaking.value = ref;
      await _tts.speak(choice.text);
    } on Object {
      speaking.value = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    speaking.value = null;
    try {
      await _tts.stop();
    } on Object {
      // Nothing was playing, or the platform has no opinion. Either is fine.
    }
  }

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts
      ..setCompletionHandler(() => speaking.value = null)
      ..setCancelHandler(() => speaking.value = null)
      ..setErrorHandler((_) => speaking.value = null);
  }
}
