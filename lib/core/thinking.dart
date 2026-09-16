/// Separating a model's reasoning from its answer.
///
/// Gemma 4 marks reasoning with `<|channel>thought` … `<channel|>`. The
/// markers are taken from the runtime's own filter rather than guessed, and
/// this runs even when thinking was switched off: the runtime only filters
/// models it knows can think, and its own note says the flag is unreliable
/// across model bundles. A leaked marker in a verse translation would be
/// worse than a redundant regex.
library;

final _thought = RegExp(r'<\|channel>thought\n.*?<channel\|>', dotAll: true);

/// A thought that never closed, because generation hit its ceiling part-way
/// through one. Without this the whole answer reads as reasoning.
final _openThought = RegExp(r'<\|channel>thought\n.*', dotAll: true);

/// The answer alone.
String withoutThinking(String raw) => raw
    .replaceAll(_thought, '')
    .replaceAll(_openThought, '')
    .replaceAll('<channel|>', '')
    .trim();

/// The reasoning and the answer, separately, so a caller can show the first
/// while waiting for the second.
({String thinking, String answer}) splitThinking(String raw) {
  final thoughts = [
    for (final match in _thought.allMatches(raw)) _inside(match.group(0)!),
    if (_openThought.firstMatch(raw) case final open?
        when !_thought.hasMatch(open.group(0)!))
      _inside(open.group(0)!),
  ];
  return (
    thinking: thoughts.where((t) => t.isNotEmpty).join('\n').trim(),
    answer: withoutThinking(raw),
  );
}

String _inside(String block) => block
    .replaceFirst('<|channel>thought\n', '')
    .replaceAll('<channel|>', '')
    .trim();
