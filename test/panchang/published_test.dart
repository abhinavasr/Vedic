import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/panchang/panchang.dart';
import 'package:vedic/panchang/place.dart';
import 'package:vedic/panchang/today.dart';

/// Against a panchang somebody publishes.
///
/// The JPL fixtures prove the astronomy; they cannot prove the conventions.
/// Whether Saptami is Saptami, which ayanāṃśa was meant, whether the month is
/// named the way a reader expects — those are only settled by comparing with a
/// panchang people actually use.
///
/// Checked against drikpanchang.com for Dublin, 17 September 2026:
///
///   Tithi      Saptami, upto full night
///   Nakṣatra   Anuradha upto 03:23 PM
///   Yoga       Vishkambha upto 08:20 AM
///   Karaṇa     Garaja upto 07:21 PM
///   Pakṣa      Shukla
///   Māsa       Bhadrapada (amānta)
///   Sunrise    07:02 AM
///   Sunset     07:36 PM
void main() {
  const dublin = Place(
    zone: 'Europe/Dublin',
    latitude: 53.3498,
    longitude: -6.2603,
    country: 'IE',
  );

  // Irish Summer Time in September. Everything below is compared in UTC:
  // Dart's DateTime(...) without `utc` is in *this machine's* zone, and
  // comparing one of those with a UTC instant is an hour of silent error.
  const ist = Duration(hours: 1);
  DateTime published(int hour, int minute) =>
      DateTime.utc(2026, 9, 17, hour, minute).subtract(ist);
  DateTime local(DateTime utc) => utc.add(ist);

  final day = panchangFor(DateTime(2026, 9, 17), dublin, offset: ist);

  test('the limbs are the ones the published panchang names', () {
    expect(day.tithi.name, 'Saptami');
    expect(day.nakshatra.name, 'Anuradha');
    expect(day.yoga.name, 'Vishkambha');
    // Drik writes it Garaja; the same karaṇa.
    expect(day.karana.name, 'Gara');
    expect(day.paksha, Paksha.shukla);
    expect(day.masa, 'Bhadrapada');
  });

  test('the boundaries land within a few minutes of the published ones', () {
    void within(DateTime? ours, DateTime want, int minutes, String what) {
      expect(ours, isNotNull, reason: what);
      final off = ours!.difference(want).inMinutes.abs();
      expect(off, lessThanOrEqualTo(minutes), reason: '$what was ${off}m out');
    }

    within(day.nakshatra.endsAt, published(15, 23), 3, 'nakṣatra');
    within(day.karana.endsAt, published(19, 21), 3, 'karaṇa');
    // The yoga is the loosest of the four, and it is the ayanāṃśa rather than
    // the astronomy: it is the one limb computed from the Sun and the Moon
    // added, so a difference in the zero point counts twice.
    within(day.yoga.endsAt, published(8, 20), 5, 'yoga');
  });

  test('a tithi that runs past midnight is said to', () {
    // Drik prints "upto full night" for this one. Ours has to agree that it
    // does not end today — printing a bare "until 8:31 AM" would be a
    // different claim from the one the maths makes.
    final ends = local(day.tithi.endsAt!);
    expect(ends.day, 18, reason: 'Saptami runs into the next morning');
  });

  test('sunrise and sunset match the published times', () {
    expect(local(day.sun.rise!).hour, 7);
    expect(local(day.sun.rise!).minute, closeTo(2, 2));
    expect(local(day.sun.set!).hour, 19);
    expect(local(day.sun.set!).minute, closeTo(36, 2));
  });
}
