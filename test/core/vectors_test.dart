import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/vectors.dart';

double floatCosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

QuantizedVector q(List<double> v) => QuantizedVector.fromFloats(v);

void main() {
  test('int8 quantisation preserves cosine similarity at 768 dims', () {
    final rng = math.Random(42);
    List<double> random() =>
        List.generate(768, (_) => rng.nextDouble() * 2 - 1);
    for (var trial = 0; trial < 50; trial++) {
      final a = random();
      final noise = random();
      final mix = rng.nextDouble();
      final b = List.generate(768, (i) => a[i] * (1 - mix) + noise[i] * mix);
      expect(
        cosine(q(a), q(b)),
        closeTo(floatCosine(a, b), 0.01),
        reason: 'trial $trial',
      );
    }
  });

  test('identical, opposite and zero vectors', () {
    final v = [0.1, -0.5, 0.25, 0.9];
    expect(cosine(q(v), q(v)), closeTo(1, 1e-9));
    expect(cosine(q(v), q([for (final x in v) -x])), closeTo(-1, 1e-9));
    expect(cosine(q(v), q([0, 0, 0, 0])), 0);
  });

  test('survives a round trip through bytes', () {
    final v = q([0.3, -0.7, 0.0, 1.0, -1.0]);
    final back = QuantizedVector.fromBytes(v.toBytes());
    expect(back.values, v.values);
    expect(back.norm, v.norm);
  });

  test('rejects mismatched dimensions and non-finite values', () {
    expect(() => cosine(q([1, 0]), q([1, 0, 0])), throwsArgumentError);
    expect(() => q([1, double.nan]), throwsArgumentError);
  });

  test('topK returns the best matches, best first, above the floor', () {
    final query = q([1, 0]);
    final candidates = [
      ('east', q([1, 0])),
      ('north', q([0, 1])),
      ('northeast', q([1, 1])),
      ('west', q([-1, 0])),
      ('east-ish', q([1, 0.1])),
    ];
    final top = topK(query, candidates, k: 3);
    expect(top.map((s) => s.item), ['east', 'east-ish', 'northeast']);

    final floored = topK(query, candidates, k: 10, minScore: 0.5);
    expect(floored.map((s) => s.item), ['east', 'east-ish', 'northeast']);

    expect(topK(query, candidates, k: 0), isEmpty);
  });
}
