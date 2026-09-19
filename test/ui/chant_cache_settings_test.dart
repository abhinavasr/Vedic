import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/audio/chant_audio.dart';
import 'package:vedic/audio/chant_download.dart';
import 'package:vedic/ui/listen_meaning.dart';
import 'package:vedic/ui/simple_screens.dart';

ChantSource sourceWith(CacheUsage usage, {required List<String> log}) =>
    ChantSource(
      downloads: ChantDownloads(
        usage: () async => usage,
        clear: () async {
          log.add('cleared');
          return usage;
        },
        download: (_) => const Stream<DownloadProgress>.empty(),
        keepAhead: (_) async {},
      ),
    );

void main() {
  tearDown(() => ChantSource.instance = ChantSource());

  testWidgets('says what the recordings take, and what was downloaded on '
      'purpose', (tester) async {
    ChantSource.instance = sourceWith(
      const CacheUsage(bytes: 42 * 1024 * 1024, files: 96, kept: 40),
      log: [],
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded chants'), findsOneWidget);
    expect(
      find.text('42 MB · 96 recordings, 40 kept for offline'),
      findsOneWidget,
    );
  });

  testWidgets('deleting asks first, and says nothing is really lost', (
    tester,
  ) async {
    final log = <String>[];
    ChantSource.instance = sourceWith(
      const CacheUsage(bytes: 8 * 1024 * 1024, files: 12),
      log: log,
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete downloaded chants?'), findsOneWidget);
    expect(find.textContaining('Nothing is lost'), findsOneWidget);

    // Backing out leaves them alone.
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-clear-chants')));
    await tester.pumpAndSettle();
    expect(log, ['cleared']);
    expect(find.textContaining('Freed 8 MB'), findsOneWidget);
  });

  testWidgets('with nothing to manage the row is not there at all', (
    tester,
  ) async {
    // A build with no vault key cannot fetch a chant, so a row reporting
    // 0 bytes would only raise a question it has no answer to.
    ChantSource.instance = ChantSource();
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded chants'), findsNothing);
  });
}
