// Where the reader is. Pure Dart, no Flutter: the panchang's inputs have to be
// testable without a phone (CLAUDE.md, "Testing").
//
// The list of places comes from the tz database's own `zone.tab`, which every
// phone already carries and which is in the public domain. 418 places, 18 KB,
// each with coordinates and the timezone that governs them — so choosing a
// place answers both questions a panchang asks about the reader at once.

/// A place the panchang can be computed for.
class Place {
  const Place({
    required this.zone,
    required this.latitude,
    required this.longitude,
    required this.country,
  });

  /// The IANA timezone, e.g. "Asia/Kolkata". This is also the identity of the
  /// place: it is what the device reports about itself, so a phone can find
  /// where it is without asking anyone for permission.
  final String zone;

  /// Degrees north, negative south.
  final double latitude;

  /// Degrees east, negative west. Sunrise moves four minutes per degree, which
  /// is the whole reason this matters.
  final double longitude;

  /// ISO 3166 two-letter code, for grouping the list.
  final String country;

  /// The city the zone is named after, e.g. "Kolkata" for "Asia/Kolkata".
  String get city => zone.split('/').last.replaceAll('_', ' ');

  /// The part before it, e.g. "Asia". Zones like "Etc/GMT+5" have one too, and
  /// those are filtered out of the list rather than shown.
  String get region => zone.split('/').first.replaceAll('_', ' ');

  @override
  String toString() => '$zone ($latitude, $longitude)';
}

/// Reads the tz database's `zone.tab`.
///
/// Its format has been stable for decades: tab-separated country code,
/// coordinates in ISO 6709 sign-degrees-minutes(-seconds), zone name, and an
/// optional comment. Comments start with `#`.
List<Place> parseZoneTable(String table) {
  final places = <Place>[];
  for (final line in table.split('\n')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final fields = line.split('\t');
    if (fields.length < 3) continue;
    final coordinates = _parseCoordinates(fields[1]);
    if (coordinates == null) continue;
    final zone = fields[2].trim();
    // "Etc/GMT+5" and friends are offsets wearing a place's clothes: no
    // coordinates worth having, and nobody lives there.
    if (zone.startsWith('Etc/')) continue;
    places.add(
      Place(
        zone: zone,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        country: fields[0].trim(),
      ),
    );
  }
  places.sort((a, b) => a.zone.compareTo(b.zone));
  return places;
}

/// ISO 6709: `+DDMM+DDDMM` or `+DDMMSS+DDDMMSS`, latitude first.
({double latitude, double longitude})? _parseCoordinates(String field) {
  final match = RegExp(
    r'^([+-]\d{4,6})([+-]\d{5,7})$',
  ).firstMatch(field.trim());
  if (match == null) return null;
  final latitude = _degrees(match.group(1)!, degreeDigits: 2);
  final longitude = _degrees(match.group(2)!, degreeDigits: 3);
  if (latitude == null || longitude == null) return null;
  return (latitude: latitude, longitude: longitude);
}

/// One signed coordinate. [degreeDigits] is 2 for latitude and 3 for
/// longitude, which is the only thing that tells the two formats apart.
double? _degrees(String raw, {required int degreeDigits}) {
  final sign = raw.startsWith('-') ? -1 : 1;
  final digits = raw.substring(1);
  // Degrees and minutes, with seconds when they are there.
  if (digits.length != degreeDigits + 2 && digits.length != degreeDigits + 4) {
    return null;
  }
  final degrees = int.tryParse(digits.substring(0, degreeDigits));
  final minutes = int.tryParse(digits.substring(degreeDigits, degreeDigits + 2));
  if (degrees == null || minutes == null) return null;
  var value = degrees + minutes / 60;
  if (digits.length == degreeDigits + 4) {
    final seconds = int.tryParse(digits.substring(degreeDigits + 2));
    if (seconds == null) return null;
    value += seconds / 3600;
  }
  return sign * value;
}

/// The place to start from, given what the device says its timezone is.
///
/// Null when the zone is not in the table, which leaves the app asking rather
/// than guessing.
Place? placeForZone(List<Place> places, String zone) {
  for (final place in places) {
    if (place.zone == zone) return place;
  }
  return null;
}

/// How far the zone's own city is from where the reader actually is, in
/// minutes of sunrise time.
///
/// A degree of longitude is four minutes of sunrise, and a timezone is not a
/// point: `Asia/Kolkata` is one zone for the whole of India, so a reader in
/// Mumbai is 15° west of the city the zone is named after — an hour of
/// sunrise. This is the error the reader removes by naming their city or
/// letting the phone find them, and it is worth showing rather than hiding.
double sunriseMinutesApart(Place place, double longitude) =>
    ((longitude - place.longitude) * 4).abs();
