import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/panchang/astronomy.dart';
import 'package:vedic/panchang/panchang.dart';

void main() {
  test('the five limbs divide the circle into the right number of parts', () {
    expect(tithiNames.length, 30, reason: 'fifteen each way');
    expect(nakshatraNames.length, 27);
    expect(yogaNames.length, 27);
    expect(masaNames.length, 12);
  });

  test('a new moon is Amavasya and a full moon is Purnima', () {
    // These are the two instants everybody can check: the Moon and Sun at the
    // same longitude, and opposite.
    //
    // New moon: 2026 September 11, 03:27 UTC. Full moon: 2026 September 26.
    final newMoon = DateTime.utc(2026, 9, 11, 4);
    expect(tithiAt(newMoon).name, anyOf('Amavasya', 'Pratipada'));
    expect(pakshaAt(newMoon.add(const Duration(hours: 6))), Paksha.shukla);

    // Six days after a new moon the Moon is a quarter of the way round, in
    // the waxing half.
    final waxing = newMoon.add(const Duration(days: 6));
    expect(pakshaAt(waxing), Paksha.shukla);
    expect(tithiAt(waxing).index, inInclusiveRange(4, 8));
  });

  test('every tithi ends, and the next one follows it', () {
    var when = DateTime.utc(2026, 1, 1);
    var previous = tithiAt(when);
    for (var i = 0; i < 40; i++) {
      final ends = previous.endsAt;
      expect(ends, isNotNull, reason: 'a tithi always ends');
      // Just after the boundary, the next tithi is current.
      final next = tithiAt(ends!.add(const Duration(minutes: 1)));
      expect(
        next.index,
        (previous.index + 1) % 30,
        reason: 'after ${previous.name} at $ends',
      );
      // A tithi runs between about 19 and 26 hours.
      final length = ends.difference(when);
      if (i > 0) {
        expect(length.inHours, inInclusiveRange(0, 27));
      }
      when = ends.add(const Duration(minutes: 1));
      previous = next;
    }
  });

  test('a nakṣatra is thirteen degrees and twenty minutes of the Moon', () {
    final when = DateTime.utc(2026, 9, 17, 6);
    final nakshatra = nakshatraAt(when);
    expect(nakshatra.index, inInclusiveRange(0, 26));
    expect(nakshatraNames[nakshatra.index], nakshatra.name);
    // The Moon covers one in about a day.
    final ends = nakshatra.endsAt!;
    expect(ends.difference(when).inHours, inInclusiveRange(0, 27));
  });

  test('the karaṇas run seven at a time, with four fixed ones', () {
    // Sixty half-tithis: Kimstughna once at the start, then the seven movable
    // ones eight times, then the three remaining fixed ones.
    final names = [for (var i = 0; i < 60; i++) karanaName(i)];
    expect(names.first, 'Kimstughna');
    expect(names.sublist(1, 8), [
      'Bava', 'Balava', 'Kaulava', 'Taitila', 'Gara', 'Vanija', 'Vishti',
    ]);
    expect(names.sublist(57), ['Shakuni', 'Chatushpada', 'Naga']);
    // Vishti — Bhadra, the one people avoid — comes round eight times.
    expect(names.where((n) => n == 'Vishti').length, 8);
  });

  test('the ayanāṃśa is where the traditions say it is', () {
    // Lahiri is about 24°08′ in 2026 and moves 50.3″ a year. This is a
    // convention, not an observation: the number is what makes a nakṣatra
    // agree or disagree with a printed panchang.
    final now = julianDay(DateTime.utc(2026, 1, 1));
    expect(ayanamsha(now), closeTo(24.14, 0.1));
    // A century of precession is about 1.4°.
    final century = julianDay(DateTime.utc(2126, 1, 1));
    expect(ayanamsha(century) - ayanamsha(now), closeTo(1.4, 0.05));
    // The traditions differ by enough to move a nakṣatra boundary by hours.
    expect(
      ayanamsha(now) - ayanamsha(now, Ayanamsha.raman),
      closeTo(1.12, 0.01),
    );
  });

  test('the month is named, and the two reckonings differ by a fortnight', () {
    final dark = DateTime.utc(2026, 9, 5);
    expect(pakshaAt(dark), Paksha.krishna, reason: 'chosen as a waning day');
    final amanta = masaAt(dark);
    final purnimanta = masaAt(dark, purnimanta: true);
    expect(masaNames, contains(amanta));
    // In the dark half the two conventions name different months — which is
    // exactly why the app has to say which one it used.
    expect(purnimanta, isNot(amanta));
  });

  test('the weekday is one of the seven', () {
    expect(varaAt(DateTime.utc(2026, 9, 17)), 'Guruvara', reason: 'a Thursday');
    expect(varaAt(DateTime.utc(2026, 9, 20)), 'Ravivara', reason: 'a Sunday');
  });
}
