import 'package:flutter/widgets.dart';

import 'assistant.dart';
import 'translation.dart';

/// The language the reader wants to read in.
///
/// One choice rather than a list: it decides which translation is shown first
/// and which one the app offers to make. Everything a pack ships stays
/// available underneath it.
class ReadingLanguage extends ChangeNotifier {
  ReadingLanguage(this.settings) {
    _code = settings?.read(_key) ?? TargetLanguage.english.code;
    _withExplanation = settings?.read(_explanationKey) == 'true';
  }

  /// The app's, replaceable in tests.
  static ReadingLanguage instance = ReadingLanguage(null);

  static const _key = 'reading.language';
  static const _explanationKey = 'reading.speakExplanation';

  final AssistantSettings? settings;

  late String _code;
  late bool _withExplanation;

  TargetLanguage get language =>
      TargetLanguage.forCode(_code) ?? TargetLanguage.english;

  set language(TargetLanguage choice) {
    if (choice.code == _code) return;
    _code = choice.code;
    settings?.write(_key, choice.code);
    notifyListeners();
  }

  /// Whether reading a verse aloud carries on into its explanation.
  bool get withExplanation => _withExplanation;

  set withExplanation(bool on) {
    if (on == _withExplanation) return;
    _withExplanation = on;
    settings?.write(_explanationKey, '\$on');
    notifyListeners();
  }

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
