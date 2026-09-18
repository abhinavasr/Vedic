import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/meditation/meditation_music.dart';
import 'package:vedic/ui/meditation_screen.dart';

void main() {
  test('every track that is not silence names an asset that is bundled', () {
    // A missing file is silent failure: the timer runs, nothing plays, and
    // nobody can tell whether the track or the phone is at fault.
    for (final music in MeditationMusic.values) {
      if (music == MeditationMusic.none) {
        expect(music.sounds, isFalse);
        continue;
      }
      expect(music.sounds, isTrue, reason: '${music.name} should play');
      expect(music.asset, startsWith('sounds/'));
      expect(
        File('assets/${music.asset}').existsSync(),
        isTrue,
        reason: '${music.asset} is named but not in assets/',
      );
    }
  });

  testWidgets('the sound can be chosen, and silence is one of the choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MeditationScreen()));
    await tester.pumpAndSettle();

    for (final music in MeditationMusic.values) {
      expect(
        find.byKey(ValueKey('music-${music.name}')),
        findsOneWidget,
        reason: '${music.label} should be offered',
      );
    }

    // Choosing one does not start the sitting: the timer is still the thing
    // being set up, and picking a sound is part of setting it up.
    await tester.tap(find.byKey(const ValueKey('music-waves')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
