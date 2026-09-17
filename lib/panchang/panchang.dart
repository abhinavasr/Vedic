import 'astronomy.dart';

// The five limbs, and the times of day that hang off sunrise.
//
// All of it is arithmetic on two longitudes and one sunrise. What is *not*
// arithmetic is the convention: which ayanāṃśa, whose sunrise, amānta or
// pūrṇimānta. Those are choices, they are named here rather than buried, and
// the app says which ones produced what it is showing.

/// The thirty tithis of a lunar month, by name.
const tithiNames = [
  'Pratipada', 'Dvitiya', 'Tritiya', 'Chaturthi', 'Panchami',
  'Shashthi', 'Saptami', 'Ashtami', 'Navami', 'Dashami',
  'Ekadashi', 'Dvadashi', 'Trayodashi', 'Chaturdashi', 'Purnima',
  'Pratipada', 'Dvitiya', 'Tritiya', 'Chaturthi', 'Panchami',
  'Shashthi', 'Saptami', 'Ashtami', 'Navami', 'Dashami',
  'Ekadashi', 'Dvadashi', 'Trayodashi', 'Chaturdashi', 'Amavasya',
];

const nakshatraNames = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
  'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni',
  'Uttara Phalguni', 'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha',
  'Jyeshtha', 'Mula', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana',
  'Dhanishtha', 'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada',
  'Revati',
];

const yogaNames = [
  'Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda',
  'Sukarma', 'Dhriti', 'Shula', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata',
  'Harshana', 'Vajra', 'Siddhi', 'Vyatipata', 'Variyana', 'Parigha', 'Shiva',
  'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti',
];

/// The seven moving karaṇas, which repeat eight times, and the four fixed ones
/// that close and open the month.
const _movableKaranas = [
  'Bava', 'Balava', 'Kaulava', 'Taitila', 'Gara', 'Vanija', 'Vishti',
];
const _fixedKaranas = ['Shakuni', 'Chatushpada', 'Naga', 'Kimstughna'];

/// The twelve lunar months.
const masaNames = [
  'Chaitra', 'Vaishakha', 'Jyeshtha', 'Ashadha', 'Shravana', 'Bhadrapada',
  'Ashwina', 'Kartika', 'Margashirsha', 'Pausha', 'Magha', 'Phalguna',
];

const _weekdays = [
  'Ravivara', 'Somavara', 'Mangalavara', 'Budhavara', 'Guruvara',
  'Shukravara', 'Shanivara',
];

/// Which definition of the zero point of the zodiac to measure from.
///
/// Nakṣatra and yoga are sidereal, and sidereal means "measured from a fixed
/// star rather than from the equinox", which drifts. How far it has drifted is
/// the ayanāṃśa, and traditions differ about it by minutes of arc — which is
/// hours of nakṣatra. Lahiri is the Indian national standard and the default.
enum Ayanamsha {
  lahiri('Lahiri (Chitrapakṣa)'),
  raman('Raman'),
  krishnamurti('Krishnamurti (KP)');

  const Ayanamsha(this.label);

  final String label;
}

/// The ayanāṃśa in degrees at [jd].
///
/// Lahiri's definition puts the zero point 180° from Spica. The linear form
/// here is the standard approximation: about 24°08′ in 2026, drifting 50.3″ a
/// year.
double ayanamsha(double jd, [Ayanamsha which = Ayanamsha.lahiri]) {
  final years = (jd - 2451545.0) / 365.25;
  final lahiri = 23.85 + years * 50.2719 / 3600;
  return switch (which) {
    Ayanamsha.lahiri => lahiri,
    // The offsets between the traditions are near enough constant over the
    // span this app covers.
    Ayanamsha.raman => lahiri - 1.1167,
    Ayanamsha.krishnamurti => lahiri - 0.0917,
  };
}

/// A sidereal longitude, for the limbs measured from the fixed zodiac.
double sidereal(double tropical, double jd, Ayanamsha which) =>
    normalise(tropical - ayanamsha(jd, which));

/// One of the five limbs: which one it is, and when it gives way to the next.
class Limb {
  const Limb({
    required this.index,
    required this.name,
    required this.endsAt,
    this.startedAt,
  });

  /// Zero-based, so it can index the names.
  final int index;
  final String name;

  /// When this one ends, in UTC. Null when it was not worth searching for.
  final DateTime? endsAt;
  final DateTime? startedAt;

  /// As it is spoken: "Krishna Ashtami" rather than "tithi 22".
  @override
  String toString() => name;
}

/// Waxing or waning.
enum Paksha {
  shukla('Shukla Paksha'),
  krishna('Krishna Paksha');

  const Paksha(this.label);

  final String label;
}

/// The angle a limb divides the circle into, and the function of Sun and Moon
/// it is measured on.
double _tithiAngle(double jd) =>
    normalise(moonLongitude(jd) - sunLongitude(jd));

double _yogaAngle(double jd, Ayanamsha a) => normalise(
  sidereal(moonLongitude(jd), jd, a) + sidereal(sunLongitude(jd), jd, a),
);

/// When the angle [of] next reaches a multiple of [step], searching forward
/// from [jd].
///
/// Bisection rather than a formula: the Moon's speed varies by a fifth over a
/// month, so anything linear is minutes out, and the boundary is exactly what
/// a panchang is read for.
DateTime? _boundary(
  double jd,
  double Function(double jd) of,
  double step, {
  double withinDays = 2.0,
}) {
  final start = of(jd);
  final target = (start / step).floor() * step + step;
  // The angle always increases; a target of 360° is the wrap back to zero.
  double gap(double at) {
    final now = of(at);
    final ahead = normalise(now - start);
    return ahead - (target - start);
  }

  var low = jd;
  var high = jd + withinDays;
  if (gap(high) < 0) return null;
  for (var i = 0; i < 60; i++) {
    final middle = (low + high) / 2;
    if (gap(middle) < 0) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return dateOf((low + high) / 2);
}

/// The tithi at [when].
Limb tithiAt(DateTime when) {
  final jd = julianDay(when);
  final index = (_tithiAngle(jd) / 12).floor() % 30;
  return Limb(
    index: index,
    name: tithiNames[index],
    endsAt: _boundary(jd, _tithiAngle, 12),
  );
}

/// The nakṣatra the Moon is in at [when].
Limb nakshatraAt(DateTime when, {Ayanamsha ayana = Ayanamsha.lahiri}) {
  final jd = julianDay(when);
  double moon(double at) => sidereal(moonLongitude(at), at, ayana);
  final index = (moon(jd) / (360 / 27)).floor() % 27;
  return Limb(
    index: index,
    name: nakshatraNames[index],
    endsAt: _boundary(jd, moon, 360 / 27),
  );
}

/// The yoga at [when]: the Sun and Moon added rather than subtracted.
Limb yogaAt(DateTime when, {Ayanamsha ayana = Ayanamsha.lahiri}) {
  final jd = julianDay(when);
  double angle(double at) => _yogaAngle(at, ayana);
  final index = (angle(jd) / (360 / 27)).floor() % 27;
  return Limb(
    index: index,
    name: yogaNames[index],
    endsAt: _boundary(jd, angle, 360 / 27),
  );
}

/// The karaṇa at [when]: half a tithi.
Limb karanaAt(DateTime when) {
  final jd = julianDay(when);
  final half = (_tithiAngle(jd) / 6).floor() % 60;
  return Limb(
    index: half,
    name: karanaName(half),
    endsAt: _boundary(jd, _tithiAngle, 6),
  );
}

/// The karaṇa in the [half]-th sixth of the lunar month.
///
/// Four of the sixty are fixed and sit at the turn of the month; the other
/// seven repeat eight times between them.
String karanaName(int half) {
  if (half == 0) return _fixedKaranas[3];
  if (half >= 57) return _fixedKaranas[half - 57];
  return _movableKaranas[(half - 1) % 7];
}

/// Waxing or waning at [when].
Paksha pakshaAt(DateTime when) =>
    _tithiAngle(julianDay(when)) < 180 ? Paksha.shukla : Paksha.krishna;

/// The weekday, which in a panchang begins at sunrise rather than midnight.
String varaAt(DateTime localMidnightOrLater) =>
    _weekdays[localMidnightOrLater.weekday % 7];

/// The lunar month at [when].
///
/// Amānta months end at the new moon and pūrṇimānta at the full moon, which
/// puts a fortnight between the two answers for the same day. Both are right;
/// which one a reader expects depends on where they are from.
String masaAt(
  DateTime when, {
  bool purnimanta = false,
  Ayanamsha ayana = Ayanamsha.lahiri,
}) {
  final jd = julianDay(when);
  // The month is named for the solar sign the Sun is in when the month
  // begins, so the Sun's sidereal position gives it directly.
  final sun = sidereal(sunLongitude(jd), jd, ayana);
  var index = (sun / 30).floor() % 12;
  // A pūrṇimānta month runs a fortnight ahead of the amānta one, in the dark
  // half.
  if (purnimanta && pakshaAt(when) == Paksha.krishna) {
    index = (index + 1) % 12;
  }
  return masaNames[index];
}
