import 'dart:math' as math;

import 'astronomy.dart';

// Sunrise, sunset, moonrise, moonset — and the times of day a panchang hangs
// off them.
//
// This is the part of the panchang that depends on where the reader is.
// Tithi and nakṣatra are the same number everywhere on Earth at a given
// instant; sunrise is not, and since the day's tithi is the one current at
// sunrise, everything follows from getting this right for the right place.

const _degrees = math.pi / 180;

/// How far below the horizon the Sun's centre is at sunrise.
///
/// The standard 50 arcminutes: 34′ of refraction, and 16′ for the Sun's own
/// radius, because sunrise is when the upper limb appears and not when the
/// centre does. This is the convention Indian panchangs use, computed for the
/// sea-level horizon rather than for the height of the city.
const sunHorizon = -0.8333;

/// What a rise or set search found.
///
/// [never] and [always] are not error cases. Above the Arctic circle the Sun
/// does not rise for weeks, and a panchang for Tromsø in June has to say so
/// rather than divide by a sunrise it does not have.
enum SkyState { rises, never, always }

class RiseSet {
  const RiseSet({required this.state, this.rise, this.set, this.transit});

  final SkyState state;
  final DateTime? rise;
  final DateTime? set;

  /// Noon by the Sun rather than by the clock: when it crosses the meridian.
  final DateTime? transit;

  /// How long the Sun is up, or null where it does not rise or set.
  Duration? get dayLength {
    final rise = this.rise;
    final set = this.set;
    if (rise == null || set == null) return null;
    return set.difference(rise);
  }
}

/// Where a body is, as this needs it.
typedef _Position = ({double longitude, double latitude});

_Position _sun(double jd) => (longitude: sunLongitude(jd), latitude: 0);

_Position _moon(double jd) =>
    (longitude: moonLongitude(jd), latitude: moonLatitude(jd));

/// The body's altitude at [jd], seen from [latitude]/[longitude], in degrees.
double _altitude(
  double jd,
  _Position Function(double jd) of,
  double latitude,
  double longitude,
) {
  final place = of(jd);
  final eq = equatorial(place.longitude, place.latitude, jd);
  // The hour angle: how far the body is from the meridian of this place.
  final hourAngle =
      siderealTime(jd) + longitude - eq.rightAscension;
  final h = math.asin(
    math.sin(latitude * _degrees) * math.sin(eq.declination * _degrees) +
        math.cos(latitude * _degrees) *
            math.cos(eq.declination * _degrees) *
            math.cos(hourAngle * _degrees),
  );
  return h / _degrees;
}

/// The Moon's apparent radius plus refraction, which decides when its upper
/// limb clears the horizon. It is close enough to the Sun's to share the
/// constant, but its distance varies enough to be worth computing.
double _moonHorizon(double jd) {
  final parallax = math.asin(6378.14 / moonDistance(jd)) / _degrees;
  // Refraction, the Moon's own radius, less the parallax that lifts it.
  return 0.7275 * parallax - 0.5667;
}

/// Rise, set and transit for [day] at a place, searching the whole local day.
///
/// The search is a scan on a coarse step for a sign change in altitude, then
/// bisection — rather than the closed-form method, which assumes the body
/// moves slowly and is minutes out for the Moon.
RiseSet _riseSet(
  DateTime day,
  _Position Function(double jd) of,
  double Function(double jd) horizonAt, {
  required double latitude,
  required double longitude,
}) {
  final start = julianDay(DateTime.utc(day.year, day.month, day.day));
  double above(double jd) =>
      _altitude(jd, of, latitude, longitude) - horizonAt(jd);

  const steps = 144; // Ten minutes at a time: fine enough for any latitude.
  DateTime? rise;
  DateTime? set;
  DateTime? transit;
  var previous = above(start);
  var highest = _altitude(start, of, latitude, longitude);
  var highestAt = start;

  for (var i = 1; i <= steps; i++) {
    final jd = start + i / steps;
    final now = above(jd);
    final altitude = _altitude(jd, of, latitude, longitude);
    if (altitude > highest) {
      highest = altitude;
      highestAt = jd;
    }
    if (previous.sign != now.sign) {
      // Bisect into the ten minutes that contains the crossing.
      var low = start + (i - 1) / steps;
      var high = jd;
      for (var k = 0; k < 40; k++) {
        final middle = (low + high) / 2;
        if (above(middle).sign == previous.sign) {
          low = middle;
        } else {
          high = middle;
        }
      }
      final at = dateOf((low + high) / 2);
      if (previous < 0) {
        rise ??= at;
      } else {
        set ??= at;
      }
    }
    previous = now;
  }

  transit = dateOf(highestAt);
  if (rise == null && set == null) {
    return RiseSet(
      state: above(start) > 0 ? SkyState.always : SkyState.never,
      transit: transit,
    );
  }
  return RiseSet(state: SkyState.rises, rise: rise, set: set, transit: transit);
}

/// Sunrise, sunset and solar noon for the local day [day] at a place.
RiseSet sunRiseSet(
  DateTime day, {
  required double latitude,
  required double longitude,
}) => _riseSet(
  day,
  _sun,
  (_) => sunHorizon,
  latitude: latitude,
  longitude: longitude,
);

/// Moonrise and moonset, which can both be absent on a given day — the Moon
/// rises about fifty minutes later each day, so some days it does not.
RiseSet moonRiseSet(
  DateTime day, {
  required double latitude,
  required double longitude,
}) => _riseSet(
  day,
  _moon,
  _moonHorizon,
  latitude: latitude,
  longitude: longitude,
);

/// The eighth of the day that Rāhu is said to hold, and the others like it.
///
/// Pure arithmetic once sunrise and sunset are known: the daylight is divided
/// into eight, and which part belongs to which is fixed by the weekday. There
/// is no astronomy in this at all, which is worth knowing when comparing two
/// panchangs that disagree — they will not disagree here unless their sunrise
/// does.
class DayPart {
  const DayPart({required this.name, required this.from, required this.to});

  final String name;
  final DateTime from;
  final DateTime to;
}

/// Rāhu kāla, Yamaganda and Gulika for a day, given its sunrise and sunset.
///
/// [weekday] is Dart's: Monday is 1, Sunday is 7.
List<DayPart> inauspiciousParts(
  DateTime sunrise,
  DateTime sunset,
  int weekday,
) {
  final eighth = sunset.difference(sunrise) ~/ 8;
  DayPart part(String name, int index) => DayPart(
    name: name,
    from: sunrise.add(eighth * index),
    to: sunrise.add(eighth * (index + 1)),
  );
  // Indexed from Sunday, as the tradition counts them.
  const rahu = [7, 1, 6, 4, 5, 3, 2];
  const yama = [4, 3, 2, 1, 0, 6, 5];
  const gulika = [6, 5, 4, 3, 2, 1, 0];
  final sunday = weekday % 7;
  return [
    part('Rāhu Kāla', rahu[sunday] - 1),
    part('Yamaganda', yama[sunday]),
    part('Gulika Kāla', gulika[sunday]),
  ];
}

/// The two auspicious windows a panchang always shows.
///
/// Abhijit is the eighth part of the day around noon; Brahma muhūrta is the
/// hour and a half before sunrise, which is what the reader is being woken for.
List<DayPart> auspiciousParts(DateTime sunrise, DateTime sunset) {
  final eighth = sunset.difference(sunrise) ~/ 8;
  final noon = sunrise.add(sunset.difference(sunrise) ~/ 2);
  return [
    DayPart(
      name: 'Brahma Muhūrta',
      from: sunrise.subtract(const Duration(minutes: 96)),
      to: sunrise.subtract(const Duration(minutes: 48)),
    ),
    DayPart(
      name: 'Abhijit Muhūrta',
      from: noon.subtract(eighth ~/ 2),
      to: noon.add(eighth ~/ 2),
    ),
  ];
}
