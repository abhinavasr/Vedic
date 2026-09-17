import 'dart:math' as math;

// Where the Sun and the Moon are, computed on the phone.
//
// This is the whole of the panchang's astronomy. Tithi, nakṣatra, yoga and
// karaṇa are all functions of two longitudes; sunrise and sunset need the
// Sun's position and a latitude. Nothing else in the sky matters here, which
// is why there is no ephemeris library underneath this: the accuracy a
// panchang needs is a hundredth of what Swiss Ephemeris is built for, and the
// theories that give it are published.
//
// Sun: Meeus, *Astronomical Algorithms*, chapter 25 (the low-accuracy
// method, good to about 0.01°). Moon: chapter 47, the abridged ELP-2000/82
// with its main periodic terms, good to about 10 arcseconds in longitude.
//
// What that is worth in the units that matter: a tithi is 12° of elongation
// and the Moon gains on the Sun at about 12.19°/day, so one arcsecond is
// about two seconds of time. The measured error against JPL Horizons is
// written next to the tests that measure it, in
// test/panchang/astronomy_test.dart — not guessed here.

const _degrees = math.pi / 180;

double _sin(double d) => math.sin(d * _degrees);
double _cos(double d) => math.cos(d * _degrees);

/// Wraps [degrees] into [0, 360).
double normalise(double degrees) {
  final wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/// The shortest way round from [a] to [b], in (-180, 180].
double difference(double a, double b) {
  final gap = normalise(b - a);
  return gap > 180 ? gap - 360 : gap;
}

/// Julian Day for an instant in UTC.
DateTime _utc(DateTime when) => when.isUtc ? when : when.toUtc();

double julianDay(DateTime when) {
  final t = _utc(when);
  var year = t.year;
  var month = t.month;
  if (month <= 2) {
    year -= 1;
    month += 12;
  }
  final a = (year / 100).floor();
  // Gregorian from 1582; the app never asks about earlier, but the correction
  // costs one line and makes the function honest about its own domain.
  final b = t.isBefore(DateTime.utc(1582, 10, 15)) ? 0 : 2 - a + (a / 4).floor();
  final day =
      t.day +
      (t.hour + (t.minute + (t.second + t.millisecond / 1000) / 60) / 60) / 24;
  return (365.25 * (year + 4716)).floor() +
      (30.6001 * (month + 1)).floor() +
      day +
      b -
      1524.5;
}

/// The instant a Julian Day names, in UTC.
DateTime dateOf(double jd) {
  final z = (jd + 0.5).floor();
  final f = jd + 0.5 - z;
  var a = z;
  if (z >= 2299161) {
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    a = z + 1 + alpha - (alpha / 4).floor();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floor();
  final d = (365.25 * c).floor();
  final e = ((b - d) / 30.6001).floor();
  final dayWithFraction = b - d - (30.6001 * e).floor() + f;
  final day = dayWithFraction.floor();
  final month = e < 14 ? e - 1 : e - 13;
  final year = month > 2 ? c - 4716 : c - 4715;
  final ms = ((dayWithFraction - day) * 86400000).round();
  return DateTime.utc(year, month, day).add(Duration(milliseconds: ms));
}

/// The difference between Terrestrial Time and Universal Time, in seconds.
///
/// The Earth's rotation is not a clock. Ignoring this puts the Moon about
/// forty arcseconds out at the ends of the range the app covers, which is over
/// a minute of tithi time — more than the whole error budget.
///
/// Espenak & Meeus's polynomial expressions, for 1900 onwards.
double deltaT(double year) {
  if (year < 1920) {
    final t = year - 1900;
    return -2.79 +
        1.494119 * t -
        0.0598939 * t * t +
        0.0061966 * t * t * t -
        0.000197 * t * t * t * t;
  }
  if (year < 1941) {
    final t = year - 1920;
    return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t;
  }
  if (year < 1961) {
    final t = year - 1950;
    return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547;
  }
  if (year < 1986) {
    final t = year - 1975;
    return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718;
  }
  if (year < 2005) {
    final t = year - 2000;
    return 63.86 +
        0.3345 * t -
        0.060374 * t * t +
        0.0017275 * t * t * t +
        0.000651814 * t * t * t * t +
        0.00002373599 * t * t * t * t * t;
  }
  if (year < 2050) {
    final t = year - 2000;
    return 62.92 + 0.32217 * t + 0.005589 * t * t;
  }
  if (year < 2150) {
    final u = (year - 1820) / 100;
    return -20 + 32 * u * u - 0.5628 * (2150 - year);
  }
  final u = (year - 1820) / 100;
  return -20 + 32 * u * u;
}

/// Julian centuries of Terrestrial Time since J2000.
double _centuries(double jd) {
  final year = 2000 + (jd - 2451545.0) / 365.25;
  final tt = jd + deltaT(year) / 86400;
  return (tt - 2451545.0) / 36525;
}

/// The nutation in longitude, in degrees, to the accuracy this needs.
double _nutation(double t) {
  final omega = 125.04452 - 1934.136261 * t;
  final l = 280.4665 + 36000.7698 * t;
  final lp = 218.3165 + 481267.8813 * t;
  return (-17.20 * _sin(omega) -
          1.32 * _sin(2 * l) -
          0.23 * _sin(2 * lp) +
          0.21 * _sin(2 * omega)) /
      3600;
}

/// Apparent geocentric ecliptic longitude of the Sun, in degrees.
double sunLongitude(double jd) {
  final t = _centuries(jd);
  final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
  final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
  final c =
      (1.914602 - 0.004817 * t - 0.000014 * t * t) * _sin(m) +
      (0.019993 - 0.000101 * t) * _sin(2 * m) +
      0.000289 * _sin(3 * m);
  final trueLongitude = l0 + c;
  // Aberration, and the nutation that moves the equinox the longitude is
  // measured from.
  final omega = 125.04 - 1934.136 * t;
  return normalise(trueLongitude - 0.00569 - 0.00478 * _sin(omega));
}

// The Moon's periodic terms: Meeus 47.A (longitude and distance) and 47.B
// (latitude). Each row is the multiple of D, M, M′ and F, then the coefficient
// of the sine term in units of 1e-6 degrees.
const _moonLongitudeTerms = <List<double>>[
  [0, 0, 1, 0, 6288774],
  [2, 0, -1, 0, 1274027],
  [2, 0, 0, 0, 658314],
  [0, 0, 2, 0, 213618],
  [0, 1, 0, 0, -185116],
  [0, 0, 0, 2, -114332],
  [2, 0, -2, 0, 58793],
  [2, -1, -1, 0, 57066],
  [2, 0, 1, 0, 53322],
  [2, -1, 0, 0, 45758],
  [0, 1, -1, 0, -40923],
  [1, 0, 0, 0, -34720],
  [0, 1, 1, 0, -30383],
  [2, 0, 0, -2, 15327],
  [0, 0, 1, 2, -12528],
  [0, 0, 1, -2, 10980],
  [4, 0, -1, 0, 10675],
  [0, 0, 3, 0, 10034],
  [4, 0, -2, 0, 8548],
  [2, 1, -1, 0, -7888],
  [2, 1, 0, 0, -6766],
  [1, 0, -1, 0, -5163],
  [1, 1, 0, 0, 4987],
  [2, -1, 1, 0, 4036],
  [2, 0, 2, 0, 3994],
  [4, 0, 0, 0, 3861],
  [2, 0, -3, 0, 3665],
  [0, 1, -2, 0, -2689],
  [2, 0, -1, 2, -2602],
  [2, -1, -2, 0, 2390],
  [1, 0, 1, 0, -2348],
  [2, -2, 0, 0, 2236],
  [0, 1, 2, 0, -2120],
  [0, 2, 0, 0, -2069],
  [2, -2, -1, 0, 2048],
  [2, 0, 1, -2, -1773],
  [2, 0, 0, 2, -1595],
  [4, -1, -1, 0, 1215],
  [0, 0, 2, 2, -1110],
  [3, 0, -1, 0, -892],
  [2, 1, 1, 0, -810],
  [4, -1, -2, 0, 759],
  [0, 2, -1, 0, -713],
  [2, 2, -1, 0, -700],
  [2, 1, -2, 0, 691],
  [2, -1, 0, -2, 596],
  [4, 0, 1, 0, 549],
  [0, 0, 4, 0, 537],
  [4, -1, 0, 0, 520],
  [1, 0, -2, 0, -487],
  [2, 1, 0, -2, -399],
  [0, 0, 2, -2, -381],
  [1, 1, 1, 0, 351],
  [3, 0, -2, 0, -340],
  [4, 0, -3, 0, 330],
  [2, -1, 2, 0, 327],
  [0, 2, 1, 0, -323],
  [1, 1, -1, 0, 299],
  [2, 0, 3, 0, 294],
];

const _moonLatitudeTerms = <List<double>>[
  [0, 0, 0, 1, 5128122],
  [0, 0, 1, 1, 280602],
  [0, 0, 1, -1, 277693],
  [2, 0, 0, -1, 173237],
  [2, 0, -1, 1, 55413],
  [2, 0, -1, -1, 46271],
  [2, 0, 0, 1, 32573],
  [0, 0, 2, 1, 17198],
  [2, 0, 1, -1, 9266],
  [0, 0, 2, -1, 8822],
  [2, -1, 0, -1, 8216],
  [2, 0, -2, -1, 4324],
  [2, 0, 1, 1, 4200],
  [2, 1, 0, -1, -3359],
  [2, -1, -1, 1, 2463],
  [2, -1, 0, 1, 2211],
  [2, -1, -1, -1, 2065],
  [0, 1, -1, -1, -1870],
  [4, 0, -1, -1, 1828],
  [0, 1, 0, 1, -1794],
  [0, 0, 0, 3, -1749],
  [0, 1, -1, 1, -1565],
  [1, 0, 0, 1, -1491],
  [0, 1, 1, 1, -1475],
  [0, 1, 1, -1, -1410],
  [0, 1, 0, -1, -1344],
  [1, 0, 0, -1, -1335],
  [0, 0, 3, 1, 1107],
  [4, 0, 0, -1, 1021],
  [4, 0, -1, 1, 833],
  [0, 0, 1, -3, 777],
  [4, 0, -2, 1, 671],
  [2, 0, 0, -3, 607],
  [2, 0, 2, -1, 596],
  [2, -1, 1, -1, 491],
  [2, 0, -2, 1, -451],
  [0, 0, 3, -1, 439],
  [2, 0, 2, 1, 422],
  [2, 0, -3, -1, 421],
  [2, 1, -1, 1, -366],
  [2, 1, 0, 1, -351],
  [4, 0, 0, 1, 331],
  [2, -1, 1, 1, 315],
  [2, -2, 0, -1, 302],
  [0, 0, 1, 3, -283],
  [2, 1, 1, -1, -229],
  [1, 1, 0, -1, 223],
  [1, 1, 0, 1, 223],
  [0, 1, -2, -1, -220],
  [2, 1, -1, -1, -220],
  [1, 0, 1, 1, -185],
  [2, -1, -2, -1, 181],
  [0, 1, 2, 1, -177],
  [4, 0, -2, -1, 176],
  [4, -1, -1, -1, 166],
  [1, 0, 1, -1, -164],
  [4, 0, 1, -1, 132],
  [1, 0, -1, -1, -119],
  [4, -1, 0, -1, 115],
  [2, -2, 0, 1, 107],
];

/// The Moon's arguments at [t], Julian centuries of TT since J2000.
({double d, double m, double mp, double f, double lp, double e}) _moonArgs(
  double t,
) {
  final lp =
      218.3164477 +
      481267.88123421 * t -
      0.0015786 * t * t +
      t * t * t / 538841 -
      t * t * t * t / 65194000;
  final d =
      297.8501921 +
      445267.1114034 * t -
      0.0018819 * t * t +
      t * t * t / 545868 -
      t * t * t * t / 113065000;
  final m =
      357.5291092 +
      35999.0502909 * t -
      0.0001536 * t * t +
      t * t * t / 24490000;
  final mp =
      134.9633964 +
      477198.8675055 * t +
      0.0087414 * t * t +
      t * t * t / 69699 -
      t * t * t * t / 14712000;
  final f =
      93.2720950 +
      483202.0175233 * t -
      0.0036539 * t * t -
      t * t * t / 3526000 +
      t * t * t * t / 863310000;
  // The Earth's orbit is slowly becoming less eccentric, which matters for the
  // terms that depend on the Sun's anomaly.
  final e = 1 - 0.002516 * t - 0.0000074 * t * t;
  return (d: d, m: m, mp: mp, f: f, lp: lp, e: e);
}

double _eccentricity(double e, double m) => switch (m.abs()) {
  0 => 1.0,
  1 => e,
  _ => e * e,
};

/// Apparent geocentric ecliptic longitude of the Moon, in degrees.
double moonLongitude(double jd) {
  final t = _centuries(jd);
  final a = _moonArgs(t);
  // The three additive arguments: Venus, Jupiter and the flattening of the
  // Earth. Small, but larger than the accuracy claimed without them.
  final a1 = 119.75 + 131.849 * t;
  final a2 = 53.09 + 479264.290 * t;

  var sum = 0.0;
  for (final term in _moonLongitudeTerms) {
    final argument =
        term[0] * a.d + term[1] * a.m + term[2] * a.mp + term[3] * a.f;
    sum += term[4] * _eccentricity(a.e, term[1]) * _sin(argument);
  }
  sum +=
      3958 * _sin(a1) +
      1962 * _sin(a.lp - a.f) +
      318 * _sin(a2);

  return normalise(a.lp + sum / 1000000 + _nutation(t));
}

/// Geocentric ecliptic latitude of the Moon, in degrees.
double moonLatitude(double jd) {
  final t = _centuries(jd);
  final a = _moonArgs(t);
  final a1 = 119.75 + 131.849 * t;
  final a3 = 313.45 + 481266.484 * t;

  var sum = 0.0;
  for (final term in _moonLatitudeTerms) {
    final argument =
        term[0] * a.d + term[1] * a.m + term[2] * a.mp + term[3] * a.f;
    sum += term[4] * _eccentricity(a.e, term[1]) * _sin(argument);
  }
  sum +=
      -2235 * _sin(a.lp) +
      382 * _sin(a3) +
      175 * _sin(a1 - a.f) +
      175 * _sin(a1 + a.f) +
      127 * _sin(a.lp - a.mp) -
      115 * _sin(a.lp + a.mp);

  return sum / 1000000;
}

/// The Moon's distance from the Earth, in kilometres. Needed for its apparent
/// size, which decides when its upper limb clears the horizon.
double moonDistance(double jd) {
  final t = _centuries(jd);
  final a = _moonArgs(t);
  var sum = 0.0;
  for (final term in _moonLongitudeTerms) {
    final argument =
        term[0] * a.d + term[1] * a.m + term[2] * a.mp + term[3] * a.f;
    // 47.A's cosine coefficients are not carried here; the leading terms give
    // the distance to a few hundred kilometres, which moves the Moon's
    // apparent radius by under an arcminute.
    sum += term[4] * _eccentricity(a.e, term[1]) * _cos(argument) * -0.0459;
  }
  return 385000.56 + sum / 1000;
}

/// The obliquity of the ecliptic at [jd], in degrees.
double obliquity(double jd) {
  final t = _centuries(jd);
  return 23.439291 -
      0.0130042 * t -
      0.00000016 * t * t +
      0.000000504 * t * t * t;
}

/// Right ascension and declination for an ecliptic position, in degrees.
({double rightAscension, double declination}) equatorial(
  double longitude,
  double latitude,
  double jd,
) {
  final e = obliquity(jd);
  final ra = math.atan2(
    _sin(longitude) * _cos(e) - math.tan(latitude * _degrees) * _sin(e),
    _cos(longitude),
  );
  final dec = math.asin(
    _sin(latitude) * _cos(e) + _cos(latitude) * _sin(e) * _sin(longitude),
  );
  return (
    rightAscension: normalise(ra / _degrees),
    declination: dec / _degrees,
  );
}

/// Greenwich mean sidereal time at [jd], in degrees.
double siderealTime(double jd) {
  final t = (jd - 2451545.0) / 36525;
  return normalise(
    280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000,
  );
}
