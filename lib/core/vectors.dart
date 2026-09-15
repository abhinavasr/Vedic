import 'dart:math' as math;
import 'dart:typed_data';

/// An embedding quantised to int8, as stored in SQLite.
///
/// Symmetric per-vector scaling. The scale is not stored because cosine
/// similarity does not depend on it. 20k chunks × 768 dims is ~15 MB this way
/// instead of ~61 MB as float32.
class QuantizedVector {
  QuantizedVector(this.values) : norm = _norm(values);

  factory QuantizedVector.fromFloats(List<double> embedding) {
    var maxAbs = 0.0;
    for (final x in embedding) {
      if (!x.isFinite) {
        throw ArgumentError.value(
          x,
          'embedding',
          'contains a non-finite value',
        );
      }
      maxAbs = math.max(maxAbs, x.abs());
    }
    final q = Int8List(embedding.length);
    if (maxAbs > 0) {
      final scale = 127 / maxAbs;
      for (var i = 0; i < embedding.length; i++) {
        q[i] = (embedding[i] * scale).round().clamp(-127, 127);
      }
    }
    return QuantizedVector(q);
  }

  factory QuantizedVector.fromBytes(Uint8List bytes) => QuantizedVector(
    Int8List.fromList(
      bytes.buffer.asInt8List(bytes.offsetInBytes, bytes.length),
    ),
  );

  final Int8List values;

  /// Precomputed so each comparison in a search is a single dot product.
  final double norm;

  int get dimensions => values.length;

  Uint8List toBytes() => Uint8List.fromList(
    values.buffer.asUint8List(values.offsetInBytes, values.length),
  );

  static double _norm(Int8List v) {
    var sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }
}

/// Cosine similarity in [-1, 1]. A zero vector is similar to nothing.
double cosine(QuantizedVector a, QuantizedVector b) {
  final x = a.values;
  final y = b.values;
  if (x.length != y.length) {
    throw ArgumentError('Dimension mismatch: ${x.length} vs ${y.length}');
  }
  if (a.norm == 0 || b.norm == 0) return 0;
  var dot = 0;
  for (var i = 0; i < x.length; i++) {
    dot += x[i] * y[i];
  }
  return dot / (a.norm * b.norm);
}

class Scored<T> {
  const Scored(this.item, this.score);

  final T item;
  final double score;
}

/// Exact brute-force search: the [k] best [candidates] by cosine similarity,
/// best first, ignoring any below [minScore].
///
/// Exact by design: no approximate index to build, tune or corrupt. Revisit
/// only with an on-device measurement showing it is too slow.
List<Scored<T>> topK<T>(
  QuantizedVector query,
  Iterable<(T, QuantizedVector)> candidates, {
  required int k,
  double minScore = double.negativeInfinity,
}) {
  final best = <Scored<T>>[];
  if (k <= 0) return best;
  for (final (item, vector) in candidates) {
    final score = cosine(query, vector);
    if (score < minScore) continue;
    if (best.length == k && score <= best.last.score) continue;
    var i = best.length;
    while (i > 0 && best[i - 1].score < score) {
      i--;
    }
    best.insert(i, Scored(item, score));
    if (best.length > k) best.removeLast();
  }
  return best;
}
