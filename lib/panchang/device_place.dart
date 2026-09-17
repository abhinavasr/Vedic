import 'package:flutter/services.dart';

import 'place.dart';

// Finding the reader without asking them, and without asking anybody else.
//
// The device's own timezone names a place; the tz database, bundled with the
// app, gives that place's coordinates. No location API, no permission dialog,
// no network, nothing that can be refused or that costs money per lookup.

const _platform = MethodChannel('com.batiyao.veda/notifications');

/// The IANA timezone this phone is set to, e.g. "Asia/Kolkata".
///
/// Flutter has no way to ask, so the platform is asked directly. A phone that
/// will not answer leaves this null and the caller falls back.
Future<String?> deviceZone() async {
  try {
    return await _platform.invokeMethod<String>('timezone');
  } on Object {
    return null;
  }
}

/// The bundled tz place table.
Future<List<Place>> bundledPlaces([AssetBundle? bundle]) async {
  final table = await (bundle ?? rootBundle).loadString(
    'assets/timezones/zone.tab',
  );
  return parseZoneTable(table);
}

/// Where this phone is, as well as it can be known without asking anyone.
///
/// A starting point rather than an answer: a timezone is not a point, and
/// Asia/Kolkata is one zone for the whole of India, so a reader in Mumbai has
/// a sunrise an hour from the one this returns until they say where they are.
Future<Place> devicePlace({AssetBundle? bundle}) async {
  final zone = await deviceZone();
  if (zone == null) return fallbackPlace;
  try {
    return placeForZone(await bundledPlaces(bundle), zone) ?? fallbackPlace;
  } on Object {
    return fallbackPlace;
  }
}
