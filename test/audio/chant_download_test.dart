import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/audio/chant_audio.dart';
import 'package:vedic/audio/chant_download.dart';

ChantRequest verse(String ref) => ChantRequest(
  packId: 'rigveda.sa',
  workSlug: 'rigveda',
  ref: ref,
  text: 'अ॒ग्निमी॑ळे पु॒रोहि॑तं $ref',
);

class CountingServer implements ServerAudioSource {
  CountingServer({this.missing = const {}});
  final Set<String> missing;
  final fetched = <String>[];

  @override
  String get voiceId => 'vagdhenu@1';

  @override
  Future<List<int>?> fetch(ChantRequest request) async {
    fetched.add(request.ref);
    if (missing.contains(request.ref)) return null;
    return List<int>.filled(2048, 7);
  }
}

void main() {
  late Directory temp;
  late ChantCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-download-');
    cache = ChantCache(
      Directory(p.join(temp.path, 'chants')),
      // Small enough that a download of four would evict its own earlier
      // verses if pinning did not hold them.
      maxBytes: 5000,
    );
  });
  tearDown(() => temp.delete(recursive: true));

  ChantDownloader downloaderFor(CountingServer server) => ChantDownloader(
    service: ChantAudioService(cache: cache, server: server),
    cache: cache,
  );

  test('a downloaded book survives the eviction that a listened-to one does '
      'not', () async {
    final server = CountingServer();
    final downloader = downloaderFor(server);
    final book = [for (var i = 1; i <= 4; i++) verse('1.1.$i')];

    await downloader.download(book, server.voiceId).last;

    // Four verses of 2 KB against a 5 KB ceiling: without pinning most of
    // this would have been thrown away on the way in, and the reader would
    // have found the book half there on the train.
    final usage = await cache.usage();
    expect(usage.files, 4);
    expect(usage.kept, 4);
    for (final request in book) {
      expect(await cache.has(request, server.voiceId), isTrue);
    }
  });

  test('reading ahead does not pin, so it is evicted like anything else',
      () async {
    final server = CountingServer();
    final downloader = downloaderFor(server);

    await downloader.keepAhead([for (var i = 1; i <= 4; i++) verse('2.2.$i')]);

    final usage = await cache.usage();
    // Only two were fetched — it works two verses ahead, not four.
    expect(server.fetched.length, ChantDownloader.lookAhead);
    expect(usage.kept, 0, reason: 'nothing the reader did not ask for is kept');
  });

  test('what is already here is kept without being fetched again', () async {
    final server = CountingServer();
    final downloader = downloaderFor(server);
    final book = [verse('3.1.1'), verse('3.1.2')];

    await downloader.download(book, server.voiceId).last;
    expect(server.fetched.length, 2);

    await downloader.download(book, server.voiceId).last;
    expect(
      server.fetched.length,
      2,
      reason: 'downloading a book twice must not fetch it twice',
    );
  });

  test('a verse that will not come down does not stop the rest', () async {
    final server = CountingServer(missing: {'4.1.2'});
    final downloader = downloaderFor(server);
    final book = [verse('4.1.1'), verse('4.1.2'), verse('4.1.3')];

    final last = await downloader.download(book, server.voiceId).last;

    expect(last.done, 2);
    expect(last.failed, 1);
    expect(last.finished, isTrue);
    expect(server.fetched, ['4.1.1', '4.1.2', '4.1.3']);
  });

  test('releasing a book lets eviction have it back', () async {
    final server = CountingServer();
    final downloader = downloaderFor(server);
    final book = [for (var i = 1; i <= 3; i++) verse('5.1.$i')];

    await downloader.download(book, server.voiceId).last;
    expect((await cache.usage()).kept, 3);

    await downloader.release(book, server.voiceId);
    expect((await cache.usage()).kept, 0);
  });

  test('clearing takes everything, pinned or not', () async {
    final server = CountingServer();
    final downloader = downloaderFor(server);
    await downloader.download([verse('6.1.1')], server.voiceId).last;
    await downloader.keepAhead([verse('6.1.2')]);

    final before = await cache.clear();
    expect(before.files, 2);
    expect((await cache.usage()).isEmpty, isTrue);
  });

  test('sizes read the way a storage screen says them', () {
    expect(const CacheUsage(bytes: 0, files: 0).size, '0 bytes');
    expect(const CacheUsage(bytes: 2048, files: 1).size, '2 KB');
    expect(const CacheUsage(bytes: 5 * 1024 * 1024, files: 1).size, '5 MB');
    expect(
      const CacheUsage(bytes: 3 * 1024 * 1024 * 1024, files: 1).size,
      '3.0 GB',
    );
  });
}
