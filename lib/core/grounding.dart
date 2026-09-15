/// A retrieved piece of a source, with how well it matched the question.
class Passage {
  const Passage({
    required this.sourceId,
    required this.sourceTitle,
    required this.locator,
    required this.text,
    required this.score,
  });

  final int sourceId;
  final String sourceTitle;

  /// Where in the source it is, e.g. "p. 12" or "2.47".
  final String locator;
  final String text;

  /// Cosine similarity to the question.
  final double score;
}

class GroundingPolicy {
  const GroundingPolicy({this.minScore = 0.55, this.maxPassages = 5});

  /// Passages scoring below this are not relevant enough to answer from.
  ///
  /// Placeholder: calibrate against the chosen embedder's scores on real
  /// documents and record the measurement here.
  final double minScore;
  final int maxPassages;
}

sealed class Grounding {
  const Grounding();
}

/// Relevant passages exist; the model may answer from them and only them.
final class Grounded extends Grounding {
  const Grounded(this.passages);

  /// Best first, at most [GroundingPolicy.maxPassages].
  final List<Passage> passages;
}

/// Nothing relevant was found. The app says it doesn't know and **never calls
/// the model**, so there is no path back to the model's own memory.
final class NothingRelevant extends Grounding {
  const NothingRelevant();
}

Grounding decideGrounding(
  Iterable<Passage> retrieved, {
  GroundingPolicy policy = const GroundingPolicy(),
}) {
  // `NaN >= x` is false, so a broken score is never treated as relevant.
  final relevant = retrieved.where((p) => p.score >= policy.minScore).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  if (relevant.isEmpty) return const NothingRelevant();
  return Grounded(List.unmodifiable(relevant.take(policy.maxPassages)));
}
