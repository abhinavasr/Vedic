// What the reader hears when a verse is played.
//
// Three clips can be played for a verse — the chant, the meaning and the
// explanation — and every combination of them is somebody's way of using the
// app. Someone learning the recitation wants the chant alone; someone
// listening on a commute wants the meaning and the explanation and no
// Sanskrit; someone sitting with the text wants all three.
//
// Two of the three also have a language. The chant does not: it is a
// recording of the Sanskrit and there is nothing to choose. But a listener may
// well want the meaning in Hindi and the explanation in English — reading in
// one language and thinking in another is ordinary here — so each carries its
// own, and either can be left to follow the app's reading language.
//
// Order is fixed when more than one is on: chant, then meaning, then
// explanation. It is the order of a traditional reading, and a choice the
// listener does not have to make.

class ListenMix {
  const ListenMix({
    this.chant = false,
    this.meaning = true,
    this.explanation = false,
    this.meaningLanguage,
    this.explanationLanguage,
  });

  /// The recitation, as recorded. Never synthesised: a chant read out by a
  /// phone was tried and was not worth offering.
  final bool chant;

  /// The translation, read aloud.
  final bool meaning;

  /// The explanation that follows it.
  final bool explanation;

  /// The language the meaning is read in. Null follows the app's reading
  /// language, which is what most people want and none of them should have to
  /// set twice.
  final String? meaningLanguage;

  /// The language the explanation is read in. Null follows the meaning.
  final String? explanationLanguage;

  /// Nothing selected. Allowed as a value so that turning the last clip off is
  /// not a special case in the UI, though a play control offers nothing here.
  bool get isSilent => !chant && !meaning && !explanation;

  /// The language to read the meaning in, given the app's [reading] language.
  String meaningIn(String reading) => meaningLanguage ?? reading;

  /// And the explanation, which follows the meaning unless told otherwise.
  String explanationIn(String reading) =>
      explanationLanguage ?? meaningIn(reading);

  ListenMix with_({
    bool? chant,
    bool? meaning,
    bool? explanation,
    String? meaningLanguage,
    String? explanationLanguage,
    bool clearMeaningLanguage = false,
    bool clearExplanationLanguage = false,
  }) => ListenMix(
    chant: chant ?? this.chant,
    meaning: meaning ?? this.meaning,
    explanation: explanation ?? this.explanation,
    meaningLanguage: clearMeaningLanguage
        ? null
        : meaningLanguage ?? this.meaningLanguage,
    explanationLanguage: clearExplanationLanguage
        ? null
        : explanationLanguage ?? this.explanationLanguage,
  );

  /// Short and stable, for settings. Not shown to anyone.
  String get code => [
    if (chant) 'c',
    if (meaning) 'm${meaningLanguage == null ? '' : ':$meaningLanguage'}',
    if (explanation)
      'e${explanationLanguage == null ? '' : ':$explanationLanguage'}',
  ].join(',');

  static ListenMix? parse(String? code) {
    if (code == null) return null;
    if (code.isEmpty) return const ListenMix(meaning: false);
    var chant = false, meaning = false, explanation = false;
    String? meaningLanguage, explanationLanguage;
    for (final part in code.split(',')) {
      final clip = part.split(':');
      final language = clip.length > 1 ? clip[1] : null;
      // An unknown clip means a newer version wrote this, so take nothing
      // from it rather than half of it.
      switch (clip.first) {
        case 'c':
          chant = true;
        case 'm':
          meaning = true;
          meaningLanguage = language;
        case 'e':
          explanation = true;
          explanationLanguage = language;
        default:
          return null;
      }
    }
    return ListenMix(
      chant: chant,
      meaning: meaning,
      explanation: explanation,
      meaningLanguage: meaningLanguage,
      explanationLanguage: explanationLanguage,
    );
  }

  /// What the listener is about to hear, in the order they will hear it.
  ///
  /// [nameOf] turns a language code into its name. Languages are named only
  /// where they differ, so the common case reads as a sentence rather than a
  /// specification.
  String describe({
    required String reading,
    required String Function(String code) nameOf,
  }) {
    final meaningCode = meaningIn(reading);
    final explanationCode = explanationIn(reading);
    final same = meaningCode == explanationCode;
    final parts = [
      if (chant) 'the chant',
      if (meaning && explanation && same)
        'the meaning and the explanation in ${nameOf(meaningCode)}'
      else ...[
        if (meaning) 'the meaning in ${nameOf(meaningCode)}',
        if (explanation) 'the explanation in ${nameOf(explanationCode)}',
      ],
    ];
    if (parts.isEmpty) return 'Nothing selected';
    final body = parts.length == 1
        ? parts.first
        : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
    return body.substring(0, 1).toUpperCase() + body.substring(1);
  }

  @override
  bool operator ==(Object other) =>
      other is ListenMix &&
      other.chant == chant &&
      other.meaning == meaning &&
      other.explanation == explanation &&
      other.meaningLanguage == meaningLanguage &&
      other.explanationLanguage == explanationLanguage;

  @override
  int get hashCode => Object.hash(
    chant,
    meaning,
    explanation,
    meaningLanguage,
    explanationLanguage,
  );

  @override
  String toString() => 'ListenMix($code)';
}
