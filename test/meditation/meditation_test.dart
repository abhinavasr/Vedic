import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/meditation/meditation_session.dart';

final t0 = DateTime(2026, 9, 15, 6);
DateTime at(int minutes, [int seconds = 0]) =>
    t0.add(Duration(minutes: minutes, seconds: seconds));

MeditationSession started({
  int total = 20,
  int? interval = 5,
  bool endingBell = true,
}) => MeditationSession(
  MeditationSettings(
    total: Duration(minutes: total),
    interval: interval == null ? null : Duration(minutes: interval),
    endingBell: endingBell,
  ),
)..start(t0);

void main() {
  group('chime times', () {
    test('fall on each interval, never at the start or the end', () {
      expect(started().settings.chimeTimes, [
        const Duration(minutes: 5),
        const Duration(minutes: 10),
        const Duration(minutes: 15),
      ]);
    });

    test('are empty with no interval or one as long as the session', () {
      expect(started(interval: null).settings.chimeTimes, isEmpty);
      expect(started(total: 5, interval: 5).settings.chimeTimes, isEmpty);
    });
  });

  test('chimes once per interval, then rings the bell at the end', () {
    final s = started();
    expect(s.tick(at(4, 59)), isEmpty);
    expect(s.tick(at(5)), [MeditationSound.chime]);
    expect(s.tick(at(5, 1)), isEmpty);
    expect(s.tick(at(19, 59)), [
      MeditationSound.chime,
    ], reason: 'the 10 and 15 minute chimes collapse into one');
    expect(s.tick(at(20)), [MeditationSound.endingBell]);
    expect(s.phase, MeditationPhase.finished);
    expect(s.remaining(at(25)), Duration.zero);
    expect(s.tick(at(26)), isEmpty);
  });

  test('without the ending bell, the session ends silently', () {
    final s = started(interval: null, endingBell: false);
    expect(s.tick(at(21)), isEmpty);
    expect(s.phase, MeditationPhase.finished);
  });

  test('time spent paused does not count', () {
    final s = started();
    s.pause(at(3));
    expect(s.remaining(at(50)), const Duration(minutes: 17));
    expect(s.tick(at(50)), isEmpty);
    s.resume(at(50));
    expect(s.remaining(at(52)), const Duration(minutes: 15));
    expect(s.tick(at(52)), [MeditationSound.chime]);
  });

  test('ignores transitions that do not apply', () {
    final s = MeditationSession(
      const MeditationSettings(total: Duration(minutes: 1)),
    );
    s
      ..pause(t0)
      ..resume(t0);
    expect(s.phase, MeditationPhase.ready);
    expect(s.tick(at(5)), isEmpty);
    expect(s.remaining(at(5)), const Duration(minutes: 1));
  });
}
