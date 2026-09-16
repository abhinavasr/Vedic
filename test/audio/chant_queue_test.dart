import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/audio/chant_queue.dart';

ChantItem _item(String ref, {int seconds = 10}) => ChantItem(
  ref: ref,
  label: ref,
  work: 'Bhagavad Gītā',
  chapter: 'Chapter ${ref.split('.').first}',
  url: 'https://example.test/$ref',
  sha256: 'abc',
  bytes: 1000,
  durationMs: seconds * 1000,
  text: 'verse $ref',
);

final _queue = ChantQueue(
  items: [for (var i = 1; i <= 5; i++) _item('2.$i')],
);

void main() {
  test('it knows where it is and where it can go', () {
    expect(_queue.current?.ref, '2.1');
    expect(_queue.hasPrevious, isFalse);
    expect(_queue.hasNext, isTrue);

    final last = _queue.at(4);
    expect(last.current?.ref, '2.5');
    expect(last.hasNext, isFalse);
    // Asking for the next at the end stays put rather than falling off it.
    expect(last.next.current?.ref, '2.5');
    expect(_queue.previous.current?.ref, '2.1');
  });

  test('it starts where the listener left off', () {
    expect(_queue.startingAt('2.4').current?.ref, '2.4');
    // A verse this queue does not hold starts at the beginning, which is
    // what someone who opened a different chapter meant anyway.
    expect(_queue.startingAt('9.9').current?.ref, '2.1');
    expect(_queue.startingAt(null).current?.ref, '2.1');
  });

  test('it fetches the next few before they are wanted', () {
    // A listener walking down the road should not wait for each verse to
    // arrive as it starts.
    expect([for (final i in _queue.ahead()) i.ref], ['2.2', '2.3']);
    expect([for (final i in _queue.at(4).ahead()) i.ref], isEmpty);
    expect([for (final i in _queue.at(3).ahead(count: 5)) i.ref], ['2.5']);
  });

  test('it says how much is left', () {
    expect(_queue.total, const Duration(seconds: 50));
    expect(_queue.at(3).remaining, const Duration(seconds: 20));
  });

  test('an empty queue answers everything without falling over', () {
    expect(ChantQueue.empty.current, isNull);
    expect(ChantQueue.empty.hasNext, isFalse);
    expect(ChantQueue.empty.next.isEmpty, isTrue);
    expect(ChantQueue.empty.startingAt('2.1').current, isNull);
    expect(ChantQueue.empty.total, Duration.zero);
  });

  test('a length is said the way a listener would say it', () {
    expect(spokenDuration(const Duration(seconds: 42)), '42 sec');
    expect(spokenDuration(const Duration(minutes: 9, seconds: 30)), '9 min');
    expect(spokenDuration(const Duration(hours: 2)), '2 hr');
    expect(spokenDuration(const Duration(hours: 1, minutes: 5)), '1 hr 5 min');
  });

  test('the lock screen is told what is playing', () {
    final item = _item('2.47');
    expect(item.title, 'Bhagavad Gītā 2.47');
    expect(item.subtitle, 'Chapter 2');
  });
}
