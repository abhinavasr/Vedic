import 'dart:math' as math;

import 'astronomy.dart';
import 'panchang.dart';
import 'place.dart';
import 'rise_set.dart';

// A day's panchang, worked out in one place so the screen only has to lay it
// out — and so the whole of it can be tested without a phone.

class DayPanchang {
  const DayPanchang({
    required this.day,
    required this.place,
    required this.sun,
    required this.moon,
    required this.tithi,
    required this.nakshatra,
    required this.yoga,
    required this.karana,
    required this.paksha,
    required this.vara,
    required this.masa,
    required this.moonPhase,
    required this.auspicious,
    required this.inauspicious,
    required this.ayana,
    required this.purnimanta,
  });

  /// The local day this is for.
  final DateTime day;
  final Place place;

  final RiseSet sun;
  final RiseSet moon;

  /// The five limbs, each with the time it gives way to the next.
  final Limb tithi;
  final Limb nakshatra;
  final Limb yoga;
  final Limb karana;

  final Paksha paksha;
  final String vara;
  final String masa;

  /// How much of the Moon is lit, from 0 at the new moon to 1 at the full.
  final double moonPhase;

  final List<DayPart> auspicious;
  final List<DayPart> inauspicious;

  /// Which conventions produced all of the above. Shown, not hidden: two
  /// accurate panchangs disagree, and this is why.
  final Ayanamsha ayana;
  final bool purnimanta;

  /// Whether the day has a sunrise at all. Above the Arctic circle it may not,
  /// and everything anchored to sunrise is then absent rather than wrong.
  bool get hasSunrise => sun.state == SkyState.rises && sun.rise != null;

  /// What the moon looks like tonight, in words.
  String get moonPhaseName {
    final waxing = paksha == Paksha.shukla;
    if (moonPhase < 0.03) return 'New Moon';
    if (moonPhase > 0.97) return 'Full Moon';
    if (moonPhase < 0.47) return waxing ? 'Waxing Crescent' : 'Waning Crescent';
    if (moonPhase < 0.53) return waxing ? 'First Quarter' : 'Last Quarter';
    return waxing ? 'Waxing Gibbous' : 'Waning Gibbous';
  }
}

/// The panchang for [day] at [place], in that place's own local time.
///
/// [day] is a local date; the limbs are read at sunrise, because that is when
/// the Hindu day begins and which tithi is "today's" depends on it. Where the
/// Sun does not rise, they are read at the day's start instead, and the screen
/// says so.
DayPanchang panchangFor(
  DateTime day,
  Place place, {
  Ayanamsha ayana = Ayanamsha.lahiri,
  bool purnimanta = false,
  Duration? offset,
}) {
  // The local day, as an instant: the reader's midnight, in UTC.
  final zone = offset ?? day.timeZoneOffset;
  final localMidnight = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).subtract(zone);

  final sun = sunRiseSet(
    localMidnight.add(const Duration(hours: 12)),
    latitude: place.latitude,
    longitude: place.longitude,
  );
  final moon = moonRiseSet(
    localMidnight.add(const Duration(hours: 12)),
    latitude: place.latitude,
    longitude: place.longitude,
  );

  // The Hindu day begins at sunrise, so that is when the limbs are read.
  final at = sun.rise ?? localMidnight;
  final jd = julianDay(at);
  final elongation = normalise(moonLongitude(jd) - sunLongitude(jd));

  return DayPanchang(
    day: DateTime(day.year, day.month, day.day),
    place: place,
    sun: sun,
    moon: moon,
    tithi: tithiAt(at),
    nakshatra: nakshatraAt(at, ayana: ayana),
    yoga: yogaAt(at, ayana: ayana),
    karana: karanaAt(at),
    paksha: pakshaAt(at),
    vara: varaAt(day),
    masa: masaAt(at, purnimanta: purnimanta, ayana: ayana),
    // The illuminated fraction, which follows from the elongation alone.
    moonPhase: (1 - _cosDegrees(elongation)) / 2,
    auspicious: sun.rise != null && sun.set != null
        ? auspiciousParts(sun.rise!, sun.set!)
        : const [],
    inauspicious: sun.rise != null && sun.set != null
        ? inauspiciousParts(sun.rise!, sun.set!, day.weekday)
        : const [],
    ayana: ayana,
    purnimanta: purnimanta,
  );
}

/// The illuminated fraction follows from the elongation alone.
double _cosDegrees(double degrees) => math.cos(degrees * math.pi / 180);
