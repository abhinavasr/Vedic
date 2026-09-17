import 'package:flutter/widgets.dart';

import '../audio/listen_mix.dart';
import 'assistant.dart';
import 'translation.dart';

/// The language the reader wants to read in.
///
/// One choice rather than a list: it decides which translation is shown first
/// and which one the app offers to make. Everything a pack ships stays
/// available underneath it.
class ReadingLanguage extends ChangeNotifier {
  ReadingLanguage(this.settings) {
    // Hindi until they say otherwise: most of the people this is for read it,
    // the packs carry it, and English is one tap away for everyone else.
    _code = settings?.read(_key) ?? TargetLanguage.hindi.code;
    // The explanation switch came first and became one of three. A phone that
    // has it set keeps what it chose.
    _mix =
        ListenMix.parse(settings?.read(_mixKey)) ??
        ListenMix(explanation: settings?.read(_explanationKey) == 'true');
  }

  /// The app's, replaceable in tests.
  static ReadingLanguage instance = ReadingLanguage(null);

  static const _key = 'reading.language';
  static const _explanationKey = 'reading.speakExplanation';
  static const _mixKey = 'reading.listenMix';

  final AssistantSettings? settings;

  late String _code;
  late ListenMix _mix;

  TargetLanguage get language =>
      TargetLanguage.forCode(_code) ?? TargetLanguage.english;

  set language(TargetLanguage choice) {
    if (choice.code == _code) return;
    _code = choice.code;
    settings?.write(_key, choice.code);
    // Choosing the app's language chooses it for what is read aloud too.
    //
    // A clip can be pinned to a language of its own — the meaning in Hindi
    // while the explanation is in English — and a pin outlives the setting
    // that was current when it was made. So someone who pinned the meaning to
    // Hindi and later switched the app to English went on hearing Hindi, with
    // the setting screen saying English and nothing explaining the
    // difference. Changing the app's language releases the pins: anyone who
    // wants one back is two taps from it, and nobody is left arguing with a
    // setting that appears to do nothing.
    mix = _mix.with_(
      clearMeaningLanguage: true,
      clearExplanationLanguage: true,
    );
    notifyListeners();
  }

  /// What playing a verse plays: any of the chant, the meaning and the
  /// explanation.
  ListenMix get mix => _mix;

  set mix(ListenMix choice) {
    if (choice == _mix) return;
    _mix = choice;
    settings?.write(_mixKey, choice.code);
    notifyListeners();
  }

  /// Whether reading a verse aloud carries on into its explanation.
  bool get withExplanation => _mix.explanation;

  set withExplanation(bool on) => mix = _mix.with_(explanation: on);

  /// Which translation to show, best first: the reader's language, then the
  /// two that packs most often carry.
  List<String> get preference => [
    _code,
    if (_code != 'en') 'en',
    if (_code != 'hi') 'hi',
  ];
}

/// Puts the reading language above the navigator, so every screen — including
/// one already open on top of another — rebuilds the moment it changes.
class ReadingLanguageScope extends InheritedNotifier<ReadingLanguage> {
  const ReadingLanguageScope({
    super.key,
    required ReadingLanguage language,
    required super.child,
  }) : super(notifier: language);

  /// The reading language, registering the caller to rebuild when it changes.
  static ReadingLanguage of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReadingLanguageScope>()
          ?.notifier ??
      ReadingLanguage.instance;
}
