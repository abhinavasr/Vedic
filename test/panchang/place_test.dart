import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/panchang/place.dart';

/// The real table, as bundled. Parsing a made-up one would prove nothing: the
/// point of this file is that the tz database's own format is read correctly.
final _places = parseZoneTable(
  File('assets/timezones/zone.tab').readAsStringSync(),
);

Place _zone(String zone) => _places.firstWhere((p) => p.zone == zone);

void main() {
  test('the bundled table covers the world', () {
    expect(_places.length, greaterThan(350));
    expect({for (final p in _places) p.country}.length, greaterThan(180));
  });

  test('coordinates are read in degrees, north and east positive', () {
    // +2232+08822 — Kolkata, 22°32'N 88°22'E.
    final kolkata = _zone('Asia/Kolkata');
    expect(kolkata.latitude, closeTo(22.533, 0.001));
    expect(kolkata.longitude, closeTo(88.367, 0.001));

    // -3652+17446 — Auckland is south of the equator and east of Greenwich.
    final auckland = _zone('Pacific/Auckland');
    expect(auckland.latitude, closeTo(-36.867, 0.001));
    expect(auckland.longitude, closeTo(174.767, 0.001));

    // +404251-0740023 — New York, in the seconds form and west of Greenwich.
    final newYork = _zone('America/New_York');
    expect(newYork.latitude, closeTo(40.714, 0.001));
    expect(newYork.longitude, closeTo(-74.006, 0.001));
  });

  test('every place is somewhere on Earth', () {
    for (final place in _places) {
      expect(place.latitude, inInclusiveRange(-90, 90), reason: place.zone);
      expect(place.longitude, inInclusiveRange(-180, 180), reason: place.zone);
    }
  });

  test('the city is the part of the zone people recognise', () {
    expect(_zone('Asia/Kolkata').city, 'Kolkata');
    expect(_zone('America/New_York').city, 'New York');
    expect(_zone('America/New_York').region, 'America');
  });

  test('offsets pretending to be places are left out', () {
    expect(_places.where((p) => p.zone.startsWith('Etc/')), isEmpty);
  });

  test('the device timezone finds a place, and an unknown one does not', () {
    expect(placeForZone(_places, 'Asia/Kolkata')?.city, 'Kolkata');
    expect(placeForZone(_places, 'Middle/Earth'), isNull);
  });

  test('a wide timezone costs an hour of sunrise', () {
    // The case that decides whether naming a city is optional. India is one
    // timezone 15° wide: a reader in Mumbai (72.87°E) who accepts the zone's
    // own city gets Kolkata's sunrise, an hour out.
    final mumbai = sunriseMinutesApart(_zone('Asia/Kolkata'), 72.8777);
    expect(mumbai, greaterThan(60));

    // Where the zone is narrow, the zone's city is good enough to use as it
    // is: the Netherlands is not worth a city picker.
    final rotterdam = sunriseMinutesApart(_zone('Europe/Amsterdam'), 4.477);
    expect(rotterdam, lessThan(2));
  });
}
