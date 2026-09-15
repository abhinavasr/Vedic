import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/audio/chant_audio.dart';

const verse = ChantRequest(
  packId: 'bhagavad-gita.sa',
  workSlug: 'bhagavad-gita',
  ref: '2.47',
  text: 'कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।',
);

class FakePacks implements PackAudioSource {
  FakePacks(this.file);
  final File? file;
  @override
  Future<File?> find(ChantRequest request) async => file;
}

class FakeServer implements ServerAudioSource {
  FakeServer({this.bytes, this.fails = false});
  final List<int>? bytes;
  final bool fails;
  var calls = 0;

  @override
  String get voiceId => 'vagdhenu@1';

  @override
  Future<List<int>?> fetch(ChantRequest request) async {
    calls++;
    if (fails) throw const SocketException('offline');
    return bytes;
  }
}

class FakeEngine implements ChantEngine {
  FakeEngine({this.voiceId = 'orpheus-sa@1', this.gate});
  @override
  final String voiceId;
  final Completer<void>? gate;
  final texts = <String>[];

  @override
  Future<List<int>> generate(String text) async {
    texts.add(text);
    await gate?.future;
    return [for (final c in text.codeUnits) c & 0xFF];
  }
}

void main() {
  late Directory temp;
  late ChantCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-audio-test-');
    cache = ChantCache(Directory(p.join(temp.path, 'cache')));
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'an installed audio pack wins; nothing is fetched or generated',
    () async {
      final packFile = File(p.join(temp.path, 'pack.wav'))
        ..writeAsBytesSync([1]);
      final server = FakeServer(bytes: [2]);
      final engine = FakeEngine();
      final audio = await ChantAudioService(
        cache: cache,
        packs: FakePacks(packFile),
        server: server,
        engine: engine,
      ).resolve(verse);

      expect(audio!.origin, ChantOrigin.pack);
      expect(audio.file.path, packFile.path);
      expect(server.calls, 0);
      expect(engine.texts, isEmpty);
    },
  );

  test(
    'server audio is downloaded once, then replayed from the cache',
    () async {
      final server = FakeServer(bytes: [7, 7, 7]);
      final engine = FakeEngine();
      final service = ChantAudioService(
        cache: cache,
        server: server,
        engine: engine,
      );

      final first = await service.resolve(verse);
      final second = await service.resolve(verse);
      expect(first!.origin, ChantOrigin.server);
      expect(second!.origin, ChantOrigin.server);
      expect(await second.file.readAsBytes(), [7, 7, 7]);
      expect(server.calls, 1);
      expect(engine.texts, isEmpty);
    },
  );

  test(
    'without server audio, generates once and replays the saved audio',
    () async {
      final server = FakeServer();
      final engine = FakeEngine();
      final service = ChantAudioService(
        cache: cache,
        server: server,
        engine: engine,
      );

      expect((await service.resolve(verse))!.origin, ChantOrigin.generated);
      expect((await service.resolve(verse))!.origin, ChantOrigin.generated);
      expect(engine.texts, [verse.text]);
    },
  );

  test('offline falls back to generating on the phone', () async {
    final engine = FakeEngine();
    final audio = await ChantAudioService(
      cache: cache,
      server: FakeServer(fails: true),
      engine: engine,
    ).resolve(verse);
    expect(audio!.origin, ChantOrigin.generated);
    expect(engine.texts, hasLength(1));
  });

  test('changed text or a new model generates fresh audio', () async {
    final engine = FakeEngine();
    final service = ChantAudioService(cache: cache, engine: engine);
    await service.resolve(verse);
    await service.resolve(
      ChantRequest(
        packId: verse.packId,
        workSlug: verse.workSlug,
        ref: verse.ref,
        text: '${verse.text} मा',
      ),
    );
    expect(engine.texts, hasLength(2));

    final upgraded = FakeEngine(voiceId: 'orpheus-sa@2');
    await ChantAudioService(cache: cache, engine: upgraded).resolve(verse);
    expect(upgraded.texts, hasLength(1));
  });

  test('simultaneous requests for the same verse generate once', () async {
    final gate = Completer<void>();
    final engine = FakeEngine(gate: gate);
    final service = ChantAudioService(cache: cache, engine: engine);

    final a = service.resolve(verse);
    final b = service.resolve(verse);
    gate.complete();
    expect((await a)!.file.path, (await b)!.file.path);
    expect(engine.texts, hasLength(1));
  });

  test('with no source at all, there is no audio', () async {
    expect(await ChantAudioService(cache: cache).resolve(verse), isNull);
    expect(
      await ChantAudioService(
        cache: cache,
        server: FakeServer(),
      ).resolve(verse),
      isNull,
    );
  });

  test('the cache evicts least recently played audio first', () async {
    final small = ChantCache(
      Directory(p.join(temp.path, 'small')),
      maxBytes: 250,
    );
    ChantRequest ref(String r) =>
        ChantRequest(packId: 'p', workSlug: 'w', ref: r, text: r);

    final a = await small.put(ref('a'), 'v', List.filled(100, 1));
    await a.setLastModified(DateTime(2026, 1, 1));
    final b = await small.put(ref('b'), 'v', List.filled(100, 2));
    await b.setLastModified(DateTime(2026, 1, 2));
    await small.get(ref('a'), 'v'); // replaying a makes b the oldest
    await small.put(ref('c'), 'v', List.filled(100, 3));

    expect(await small.get(ref('a'), 'v'), isNotNull);
    expect(await small.get(ref('b'), 'v'), isNull);
    expect(await small.get(ref('c'), 'v'), isNotNull);
  });

  test('writes a valid 16-bit mono WAV', () {
    final wav = wavFromPcm16(pcm16FromFloat([0, 1, -1, 2]), sampleRate: 24000);
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(40, Endian.little), 8);
    expect(wav.length, 44 + 8);
    expect(data.getInt16(46, Endian.little), 32767);
    expect(data.getInt16(48, Endian.little), -32767);
    expect(data.getInt16(50, Endian.little), 32767, reason: 'clipped');
  });
}
