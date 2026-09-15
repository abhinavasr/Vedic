import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/chunker.dart';

String words(int count, [String word = 'word']) =>
    List.filled(count, word).join(' ');

void expectFaithful(String source, List<TextChunk> chunks, int maxChars) {
  for (var i = 0; i < chunks.length; i++) {
    final c = chunks[i];
    expect(c.ordinal, i);
    expect(source.substring(c.start, c.end), c.text);
    expect(c.text.length, lessThanOrEqualTo(maxChars));
    expect(c.text, isNotEmpty);
    expect(c.text.trim(), c.text);
  }
}

void main() {
  test('empty and blank text give no chunks', () {
    expect(chunkText(''), isEmpty);
    expect(chunkText(' \n\t '), isEmpty);
  });

  test('short text is one trimmed chunk', () {
    final chunks = chunkText('  hello world  ');
    expect(chunks, hasLength(1));
    expect(chunks.single.text, 'hello world');
    expect(chunks.single.start, 2);
  });

  test('prefers a paragraph break', () {
    final first = words(60);
    final text = '$first\n\n${words(60, 'more')}';
    final chunks = chunkText(text, maxChars: 400, overlapChars: 50);
    expect(chunks.first.text, first);
    expectFaithful(text, chunks, 400);
  });

  test('breaks Devanagari at a danda', () {
    const line = 'धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।';
    final text = List.filled(20, line).join(' ');
    final chunks = chunkText(text, maxChars: 200, overlapChars: 30);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(c.text, endsWith('।'));
    }
    expectFaithful(text, chunks, 200);
  });

  test('chunks overlap, stay within limits and cover every word', () {
    final rng = Random(7);
    final text = List.generate(
      2000,
      (_) => String.fromCharCodes(
        List.generate(1 + rng.nextInt(12), (_) => 0x61 + rng.nextInt(26)),
      ),
    ).join(' ');
    final chunks = chunkText(text, maxChars: 300, overlapChars: 60);
    expectFaithful(text, chunks, 300);

    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].start, lessThan(chunks[i - 1].end));
      expect(chunks[i].start, greaterThan(chunks[i - 1].start));
    }

    final covered = List.filled(text.length, false);
    for (final c in chunks) {
      covered.fillRange(c.start, c.end, true);
    }
    for (var i = 0; i < text.length; i++) {
      if (text[i] != ' ') expect(covered[i], isTrue, reason: 'index $i');
    }
  });

  test('hard cuts never split a conjunct', () {
    final text = List.filled(500, 'क्ष').join();
    final chunks = chunkText(text, maxChars: 100, overlapChars: 10);
    expectFaithful(text, chunks, 100);
    for (final c in chunks) {
      expect(c.text.codeUnitAt(0), 0x0915, reason: 'starts on क');
      expect(c.text.codeUnitAt(c.text.length - 1), 0x0937, reason: 'ends on ष');
    }
  });

  test('rejects impossible settings', () {
    expect(() => chunkText('x', maxChars: 0), throwsArgumentError);
    expect(
      () => chunkText('x', maxChars: 100, overlapChars: 100),
      throwsArgumentError,
    );
    expect(() => chunkText('x', overlapChars: -1), throwsArgumentError);
  });
}
