import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/thinking.dart';

const _thought = '<|channel>thought\nThe verse is about duty.<channel|>';

void main() {
  test('leaves an answer with no reasoning alone', () {
    expect(
      withoutThinking('Your right is to action alone.'),
      'Your right is to action alone.',
    );
    expect(splitThinking('Plain answer.').thinking, isEmpty);
    expect(splitThinking('Plain answer.').answer, 'Plain answer.');
  });

  test('separates the reasoning from the answer', () {
    final split = splitThinking('$_thought Your right is to action alone.');
    expect(split.thinking, 'The verse is about duty.');
    expect(split.answer, 'Your right is to action alone.');
  });

  test('a thought cut off at the ceiling does not swallow the answer', () {
    // Without this the whole run reads as reasoning and nothing is shown.
    const cut = 'Answer first. <|channel>thought\nStill deliberating when the';
    expect(withoutThinking(cut), 'Answer first.');
  });

  test('handles several thoughts and a stray closing marker', () {
    final split = splitThinking(
      '$_thought Part one. '
      '<|channel>thought\nSecond pass.<channel|> Part two.<channel|>',
    );
    expect(split.thinking, contains('Second pass.'));
    expect(split.answer, 'Part one.  Part two.');
    expect(split.answer, isNot(contains('channel')));
  });
}
