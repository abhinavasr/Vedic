// What the reader hears when a verse is played.
//
// Three things can be played for a verse — the chant, the meaning and the
// explanation — and every combination of them is somebody's way of using the
// app. Someone learning the recitation wants the chant alone; someone
// listening on a commute wants the meaning and the explanation and no
// Sanskrit; someone sitting with the text wants all three. Rather than a list
// of named modes, the three are independent, which covers every case and
// spares the reader having to find theirs in a menu.
//
// Order is fixed when more than one is on: chant, then meaning, then
// explanation. It is the order of a traditional reading, and a choice the
// reader does not have to make.

class ListenMix {
  const ListenMix({
    this.chant = false,
    this.meaning = true,
    this.explanation = false,
  });

  /// The recitation, as recorded. Never synthesised: a chant read out by a
  /// phone was tried and was not worth offering.
  final bool chant;

  /// The translation, read aloud in the reader's language.
  final bool meaning;

  /// The explanation that follows it, in the same language as the meaning.
  final bool explanation;

  /// Nothing selected. Allowed as a value so that turning the last one off is
  /// not a special case in the UI, but a play control offers nothing here.
  bool get isSilent => !chant && !meaning && !explanation;

  ListenMix with_({bool? chant, bool? meaning, bool? explanation}) => ListenMix(
    chant: chant ?? this.chant,
    meaning: meaning ?? this.meaning,
    explanation: explanation ?? this.explanation,
  );

  /// Short and stable, for settings. Not shown to anyone.
  String get code =>
      '${chant ? 'c' : ''}${meaning ? 'm' : ''}${explanation ? 'e' : ''}';

  static ListenMix? parse(String? code) {
    if (code == null) return null;
    // An unknown letter means a newer version wrote this, so take nothing
    // from it rather than half of it.
    if (!RegExp(r'^[cme]*$').hasMatch(code)) return null;
    return ListenMix(
      chant: code.contains('c'),
      meaning: code.contains('m'),
      explanation: code.contains('e'),
    );
  }

  /// What the reader is about to hear, in the order they will hear it.
  ///
  /// [language] is the language the meaning will be read in, which is not
  /// always the one they asked for — a phone without that voice falls back.
  String describe({String? language}) {
    final spoken = language == null ? '' : ' in $language';
    final parts = [
      if (chant) 'the chant',
      if (meaning) 'the meaning$spoken',
      if (explanation) 'the explanation$spoken',
    ];
    if (parts.isEmpty) return 'Nothing selected';
    if (parts.length == 1) return _sentence(parts.first);
    return _sentence(
      '${parts.take(parts.length - 1).join(', ')} and ${parts.last}',
    );
  }

  String _sentence(String body) =>
      body.substring(0, 1).toUpperCase() + body.substring(1);

  @override
  bool operator ==(Object other) =>
      other is ListenMix &&
      other.chant == chant &&
      other.meaning == meaning &&
      other.explanation == explanation;

  @override
  int get hashCode => Object.hash(chant, meaning, explanation);

  @override
  String toString() => 'ListenMix($code)';
}
