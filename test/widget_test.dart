import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/packs/pack_store.dart';
import 'package:vedic/ui/app.dart';

PackStore emptyStore() {
  final dir = Directory.systemTemp.createTempSync('vedic-widget-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return PackStore(root: dir, trustedKeys: const [], appBuild: 1);
}

void main() {
  testWidgets('opens on the home screen once content is prepared', (
    tester,
  ) async {
    await tester.pumpWidget(
      VedicApp(store: emptyStore(), prepare: () async {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sadhana'), findsOneWidget);
    expect(find.text('Verse of the Day'), findsOneWidget);
    expect(
      find.text('Install a scripture pack to see a verse here each day.'),
      findsOneWidget,
    );
    expect(find.text('Scriptures'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
    await tester.pumpAndSettle();
    expect(find.text('No scripture installed yet.'), findsOneWidget);
  });

  testWidgets('still opens when preparing fails, and says why', (tester) async {
    await tester.pumpWidget(
      VedicApp(
        store: emptyStore(),
        prepare: () async => throw StateError('disk full'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sadhana'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });
}
