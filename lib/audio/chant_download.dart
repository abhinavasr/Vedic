import 'dart:async';

import 'chant_audio.dart';

/// How a download is going.
class DownloadProgress {
  const DownloadProgress({
    required this.done,
    required this.total,
    required this.failed,
  });

  final int done;
  final int total;
  final int failed;

  bool get finished => done + failed >= total;
  double get fraction => total == 0 ? 1 : (done + failed) / total;
}

/// Fetching a book's chants before they are wanted.
///
/// Two ways to be ahead of the reader, and they are the same machinery. One
/// is the whole book, asked for on purpose, so that a train with no signal
/// changes nothing. The other is the next few verses while reading, which
/// costs almost nothing and removes the pause between tapping play and
/// hearing anything.
class ChantDownloader {
  ChantDownloader({required this.service, required this.cache});

  final ChantAudioService service;
  final ChantCache cache;

  /// How far ahead to keep while reading.
  ///
  /// The same two the translator works ahead by. Far enough that moving on
  /// is never a wait, near enough that skimming a chapter does not pull down
  /// the whole of it.
  static const lookAhead = 2;

  StreamController<DownloadProgress>? _running;
  var _cancelled = false;

  bool get busy => _running != null;

  /// Fetches every one of [requests] that is not already here, keeping them
  /// against eviction. Reports as it goes; closes when it is done.
  ///
  /// Serial on purpose: a phone on a mobile connection should not open forty
  /// sockets, and there is nobody waiting on any single one of these.
  Stream<DownloadProgress> download(
    List<ChantRequest> requests,
    String voiceId,
  ) {
    if (_running case final running?) return running.stream;
    late final StreamController<DownloadProgress> controller;
    var started = false;
    // Started by the first listener rather than straight away. A broadcast
    // stream drops what it emits before anyone is listening, so a download
    // that got going first could finish, close, and leave the caller waiting
    // on a stream that never says anything.
    controller = StreamController<DownloadProgress>.broadcast(
      onListen: () {
        if (started) return;
        started = true;
        unawaited(_run(requests, voiceId, controller));
      },
    );
    _running = controller;
    _cancelled = false;
    return controller.stream;
  }

  Future<void> _run(
    List<ChantRequest> requests,
    String voiceId,
    StreamController<DownloadProgress> controller,
  ) async {
    var done = 0, failed = 0;
    for (final request in requests) {
      if (_cancelled) break;
      try {
        if (await cache.has(request, voiceId)) {
          await cache.pin(request, voiceId);
          done++;
        } else if (await service.resolve(request) != null) {
          await cache.pin(request, voiceId);
          done++;
        } else {
          failed++;
        }
      } on Exception {
        // One verse that will not come down must not stop the rest: a book
        // that is all there but for verse 40 is still worth having offline.
        failed++;
      }
      controller.add(
        DownloadProgress(done: done, total: requests.length, failed: failed),
      );
    }
    // Cleared before the close, not after. Closing is what wakes whoever is
    // waiting on the stream, and if they ask for another download the moment
    // they wake, they must not be handed this one back now that it is over.
    _running = null;
    await controller.close();
  }

  /// Stops after the verse in flight.
  void cancel() => _cancelled = true;

  /// Quietly fetches the next few, without keeping them.
  ///
  /// Not pinned: this is a convenience the reader did not ask for, so it
  /// lives under the same eviction as everything else that was merely
  /// listened to.
  Future<void> keepAhead(List<ChantRequest> upcoming) async {
    for (final request in upcoming.take(lookAhead)) {
      try {
        await service.resolve(request);
      } on Exception {
        // Best-effort by definition: nothing is waiting on it.
      }
    }
  }

  /// Forgets a book, so eviction may take it back.
  Future<void> release(List<ChantRequest> requests, String voiceId) async {
    for (final request in requests) {
      await cache.unpin(request, voiceId);
    }
  }
}
