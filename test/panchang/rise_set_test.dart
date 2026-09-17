import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/panchang/rise_set.dart';

/// Rise, transit and set as JPL Horizons gives them, for ten cities.
/// See test/fixtures/astronomy/README.md.
final _events = [
  for (final line
      in File(
        'test/fixtures/astronomy/rise_set.csv',
      ).readAsLinesSync().skip(1))
    if (line.trim().isNotEmpty)
      () {
        final f = line.split(',');
        return (
          body: f[0],
          city: f[1],
          longitude: double.parse(f[2]),
          latitude: double.parse(f[3]),
          when: DateTime.parse(f[4]),
          event: f[5],
        );
      }(),
];

void main() {
  test('the fixtures cover the cases that break a panchang', () {
    final cities = {for (final e in _events) e.city};
    expect(cities, contains('Delhi'));
    expect(cities, contains('Tromso'));
    expect(cities.length, 10);
  });

  test('the Sun rises and sets when JPL says it does', () {
    var worst = 0;
    var checked = 0;
    String? worstCase;
    for (final want in _events) {
      if (want.body != 'sun') continue;
      if (want.event == 'transit') continue;
      // The whole local day around the event, since the fixtures are in UTC
      // and a day boundary in UTC is the middle of the night somewhere.
      final got = sunRiseSet(
        want.when,
        latitude: want.latitude,
        longitude: want.longitude,
      );
      final ours = want.event == 'rise' ? got.rise : got.set;
      if (ours == null) continue;
      final off = ours.difference(want.when).inSeconds.abs();
      // A day's worth of difference means we found the other day's event,
      // which the search window explains rather than the maths.
      if (off > 3600) continue;
      checked++;
      if (off > worst) {
        worst = off;
        worstCase = '${want.city} ${want.event} ${want.when}';
      }
    }
    expect(checked, greaterThan(50), reason: 'should have matched many events');
    // Measured across 228 events in ten cities: median 28 seconds, ninetieth
    // percentile 52, worst 61. Horizons prints its times to the minute, so
    // thirty of those seconds are the fixture's own rounding.
    expect(
      worst,
      lessThan(90),
      reason: 'worst ${worst}s at $worstCase, over $checked events',
    );
  });

  test('the Moon rises and sets when JPL says it does', () {
    var worst = 0;
    var checked = 0;
    for (final want in _events) {
      if (want.body != 'moon') continue;
      if (want.event == 'transit') continue;
      final got = moonRiseSet(
        want.when,
        latitude: want.latitude,
        longitude: want.longitude,
      );
      final ours = want.event == 'rise' ? got.rise : got.set;
      if (ours == null) continue;
      final off = ours.difference(want.when).inSeconds.abs();
      if (off > 3600) continue;
      checked++;
      worst = off > worst ? off : worst;
    }
    expect(checked, greaterThan(40));
    // Harder than the Sun: thirteen times faster, and close enough that its
    // parallax decides when the upper limb clears the horizon. Measured across
    // 223 events: median 26 seconds, worst 85.
    expect(worst, lessThan(120), reason: 'worst ${worst}s over $checked events');
  });

  test('the midnight sun is reported, not divided by', () {
    // Tromsø in June: the fixtures contain transits and no rise or set at all.
    // A panchang that assumes every day has a sunrise breaks here.
    final midsummer = sunRiseSet(
      DateTime.utc(2026, 6, 22),
      latitude: 69.6492,
      longitude: 18.9553,
    );
    expect(midsummer.state, SkyState.always);
    expect(midsummer.rise, isNull);
    expect(midsummer.dayLength, isNull);
    expect(midsummer.transit, isNotNull, reason: 'the Sun still crosses noon');

    // And the polar night, when it does not come up at all.
    final midwinter = sunRiseSet(
      DateTime.utc(2026, 12, 21),
      latitude: 69.6492,
      longitude: 18.9553,
    );
    expect(midwinter.state, SkyState.never);
  });

  test('an ordinary day has an ordinary length', () {
    final delhi = sunRiseSet(
      DateTime.utc(2026, 3, 20),
      latitude: 28.6139,
      longitude: 77.2090,
    );
    expect(delhi.state, SkyState.rises);
    // The equinox: twelve hours, near enough, everywhere.
    expect(delhi.dayLength!.inMinutes, closeTo(12 * 60, 15));
  });

  test('the day is divided from sunrise, not from midnight', () {
    final sunrise = DateTime.utc(2026, 9, 17, 0, 35);
    final sunset = DateTime.utc(2026, 9, 17, 12, 58);
    // A Thursday.
    final parts = inauspiciousParts(sunrise, sunset, 4);
    expect(parts.map((p) => p.name), contains('Rāhu Kāla'));
    for (final part in parts) {
      expect(part.from.isBefore(part.to), isTrue);
      expect(part.from.isAfter(sunrise.subtract(const Duration(seconds: 1))), isTrue);
      expect(part.to.isBefore(sunset.add(const Duration(seconds: 1))), isTrue);
      // Each is an eighth of the daylight.
      expect(
        part.to.difference(part.from).inMinutes,
        closeTo(sunset.difference(sunrise).inMinutes / 8, 1),
      );
    }

    final good = auspiciousParts(sunrise, sunset);
    expect(good.first.name, 'Brahma Muhūrta');
    expect(good.first.to.isBefore(sunrise), isTrue, reason: 'before dawn');
    // Abhijit straddles the middle of the day.
    final noon = sunrise.add(sunset.difference(sunrise) ~/ 2);
    expect(good.last.from.isBefore(noon), isTrue);
    expect(good.last.to.isAfter(noon), isTrue);
  });
}
