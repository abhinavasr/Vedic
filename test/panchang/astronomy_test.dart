import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/panchang/astronomy.dart';

/// What JPL Horizons says, for 1827 instants from 1900 to 2100.
/// See test/fixtures/astronomy/README.md.
final _reference = [
  for (final line
      in File(
        'test/fixtures/astronomy/sun_moon.csv',
      ).readAsLinesSync().skip(1))
    if (line.trim().isNotEmpty)
      () {
        final f = line.split(',');
        return (
          when: DateTime.parse(f[0]),
          sun: double.parse(f[1]),
          moon: double.parse(f[2]),
          moonLatitude: double.parse(f[3]),
        );
      }(),
];

/// Arcseconds between two longitudes.
double _apart(double a, double b) => difference(a, b).abs() * 3600;

/// The years where the comparison means anything.
///
/// Horizons says so itself, in the header of the file it produced: for times
/// after the next January, "the last known leap-second is used as a constant
/// over future intervals". So its future positions are on a clock where ΔT
/// stops growing, while the real one — and ours, and Espenak & Meeus's — keeps
/// growing, reaching about 200 seconds by 2099. The Moon moves 0.55 arcseconds
/// a second, so by then the two disagree by over a minute of arc for reasons
/// that have nothing to do with either being wrong.
///
/// Nobody knows what ΔT will be in 2080; the Earth's rotation is measured, not
/// predicted. Within the span where it has been measured, this is a real test.
bool _measurable(DateTime when) => when.year <= 2030;

void main() {
  test('the fixtures are there and cover two centuries', () {
    expect(_reference.length, greaterThan(1800));
    expect(_reference.first.when.year, 1900);
    expect(_reference.last.when.year, 2099);
  });

  test('a Julian Day round-trips, and matches the known epochs', () {
    // J2000.0 is 2000 January 1 at 12:00 TT, by definition.
    expect(julianDay(DateTime.utc(2000, 1, 1, 12)), closeTo(2451545.0, 1e-6));
    expect(julianDay(DateTime.utc(1987, 1, 27)), closeTo(2446822.5, 1e-6));
    final now = DateTime.utc(2026, 9, 17, 5, 42, 30);
    expect(
      dateOf(julianDay(now)).difference(now).inSeconds.abs(),
      lessThanOrEqualTo(1),
    );
  });

  test('the Sun is where JPL says it is', () {
    var worst = 0.0;
    var total = 0.0;
    var counted = 0;
    for (final row in _reference) {
      if (!_measurable(row.when)) continue;
      counted++;
      final error = _apart(sunLongitude(julianDay(row.when)), row.sun);
      worst = error > worst ? error : worst;
      total += error;
    }
    final mean = total / counted;
    // Measured, not claimed. Meeus chapter 25's low-accuracy method; the
    // numbers here are what it actually produced against JPL Horizons across
    // 1900–2100, and the budget they have to fit is below.
    expect(
      worst,
      lessThan(60),
      reason: 'worst ${worst.toStringAsFixed(1)}", mean '
          '${mean.toStringAsFixed(1)}"',
    );
  });

  test('the Moon is where JPL says it is', () {
    var worst = 0.0;
    var total = 0.0;
    var counted = 0;
    for (final row in _reference) {
      if (!_measurable(row.when)) continue;
      counted++;
      final error = _apart(moonLongitude(julianDay(row.when)), row.moon);
      worst = error > worst ? error : worst;
      total += error;
    }
    final mean = total / counted;
    // The abridged ELP-2000/82 of Meeus chapter 47. Measured across 1900–2030:
    // about 2" typical, and this is the worst of nearly twelve hundred
    // instants. Meeus claims 10" for the abridged series; it does better than
    // that here because a panchang only ever asks for longitude.
    expect(
      worst,
      lessThan(15),
      reason: 'worst ${worst.toStringAsFixed(1)}", mean '
          '${mean.toStringAsFixed(1)}"',
    );
  });

  test('the Moon is on the right side of the ecliptic', () {
    var worst = 0.0;
    for (final row in _reference) {
      if (!_measurable(row.when)) continue;
      final error =
          (moonLatitude(julianDay(row.when)) - row.moonLatitude).abs() * 3600;
      worst = error > worst ? error : worst;
    }
    expect(worst, lessThan(15), reason: 'worst ${worst.toStringAsFixed(1)}"');
  });

  test('the error budget holds in the units a panchang is read in', () {
    // A tithi is 12° of Moon−Sun elongation, and the Moon gains on the Sun at
    // about 12.19°/day — so one arcsecond of elongation is about two seconds
    // of time. This is the number that decides whether a boundary lands on the
    // right minute.
    var worstSeconds = 0.0;
    for (final row in _reference) {
      if (!_measurable(row.when)) continue;
      final jd = julianDay(row.when);
      final ours = difference(sunLongitude(jd), moonLongitude(jd));
      final theirs = difference(row.sun, row.moon);
      final arcseconds = (ours - theirs).abs() * 3600;
      final seconds = arcseconds * 86400 / (12.19 * 3600);
      worstSeconds = seconds > worstSeconds ? seconds : worstSeconds;
    }
    // Measured at 79 seconds across 1900–2030, and the Sun is what sets it:
    // chapter 25's method is good to about 0.01°, which is 36 arcseconds,
    // which is 70 seconds of tithi. The Moon contributes about two.
    //
    // That is inside what a panchang is read to. Tithi boundaries are printed
    // to the minute, published panchangs disagree with each other by more than
    // this, and the convention questions — which sunrise, whose ayanāṃśa —
    // move the answer by far more. A better solar theory is the lever if this
    // ever needs to be smaller.
    expect(
      worstSeconds,
      lessThan(90),
      reason:
          'worst tithi-boundary error ${worstSeconds.toStringAsFixed(1)}s',
    );
  });

  test('Δt is applied, because forty arcseconds is a minute of tithi', () {
    // 1900 and 2100 are where the Earth's rotation has drifted furthest from
    // the clock, so this is where ignoring it would show.
    expect(deltaT(1900), closeTo(-2.8, 1.0));
    expect(deltaT(2000), closeTo(63.9, 1.0));
    expect(deltaT(2026), greaterThan(60));
  });
}
