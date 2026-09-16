import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../core/backend.dart';
import '../core/capability.dart';
import '../core/model_catalog.dart';
import '../core/output_hygiene.dart';
import 'device_facts.dart';
import 'model_host.dart';

// The on-device assistant: one model per process, one request at a time.
// Everything here degrades to absent — with no model installed the app simply
// offers to install one.

enum AssistantPhase {
  /// Nothing checked yet.
  unknown,

  /// This phone cannot run the model; [AssistantState.message] says why.
  unsupported,
  notInstalled,

  /// Asking a host whether it can serve the file, before committing the reader
  /// to 2.4 GB.
  checking,
  downloading,
  loading,
  ready,
  working,
  failed,
}

@immutable
class AssistantState {
  const AssistantState(this.phase, {this.percent, this.message, this.backend});

  final AssistantPhase phase;

  /// Download progress, 0 to 100.
  final int? percent;

  /// Why it is unsupported, or what failed.
  final String? message;

  /// The backend the model actually loaded on.
  final String? backend;

  bool get isBusy =>
      phase == AssistantPhase.checking ||
      phase == AssistantPhase.downloading ||
      phase == AssistantPhase.loading ||
      phase == AssistantPhase.working;

  bool get canAnswer =>
      phase == AssistantPhase.ready || phase == AssistantPhase.working;
}

/// A prompt for the model: the rules go in [systemInstruction], never in the
/// user turn.
class AssistantRequest {
  const AssistantRequest({
    required this.systemInstruction,
    required this.prompt,
    this.maxOutputTokens = 512,
    this.temperature = 0.2,
  });

  final String systemInstruction;
  final String prompt;
  final int maxOutputTokens;
  final double temperature;
}

/// Where the assistant remembers its few settings between runs.
abstract class AssistantSettings {
  String? read(String key);

  void write(String key, String? value);
}

class Assistant {
  Assistant({
    this.requirement = gemma4E2bIt,
    this.probe = const HostProbe(),
    this.settings,
  }) {
    final saved = settings?.read(_hostKey);
    _preferred = ModelHost.values
        .where((host) => host.name == saved)
        .firstOrNull;
    final millis = int.tryParse(settings?.read(_loadMillisKey) ?? '');
    if (millis != null && millis > 0) {
      loadEstimate = Duration(milliseconds: millis);
    }
  }

  /// The app's assistant. Replaceable in tests.
  static Assistant instance = Assistant();

  static const _hostKey = 'assistant.host';
  static const _loadMillisKey = 'assistant.loadMillis';

  /// A download that has made no progress for this long is stuck, whatever the
  /// transfer layer still believes.
  static const _stallAfter = Duration(seconds: 90);

  final ModelRequirement requirement;
  final HostProbe probe;
  final AssistantSettings? settings;

  final state = ValueNotifier<AssistantState>(
    const AssistantState(AssistantPhase.unknown),
  );

  /// How long the last load took, so the next one can show a bar rather than a
  /// spinner. The default is measured, not guessed: 62 s on a Tensor G5.
  Duration loadEstimate = const Duration(seconds: 62);

  /// How long the current load has been running, for that bar.
  final loadElapsed = ValueNotifier<Duration>(Duration.zero);

  ModelHost? _preferred;
  ModelHost? _chosen;

  /// The host in use: the reader's choice, else whichever answered.
  ModelHost get host => _preferred ?? _chosen ?? ModelHost.huggingFace;

  /// The reader's choice of host, which beats anything automatic.
  ///
  /// Hugging Face is the default and stays the default. But it is far away
  /// from some people, and a 2.4 GB download that crawls is the kind of thing
  /// somebody gives up on, so the mirror is offered rather than reasoned about.
  ModelHost? get preferredHost => _preferred;

  set preferredHost(ModelHost? host) {
    _preferred = host;
    _chosen = null;
    settings?.write(_hostKey, host?.name);
  }

  var _engineReady = false;
  InferenceModel? _model;
  CancelToken? _download;
  Timer? _stall;
  Timer? _ticker;
  var _lastPercent = -1;

  /// Requests run one at a time: concurrent inference overheats the phone or
  /// gets the app killed.
  Future<void> _queue = Future.value();

  /// Checks the phone and whether the model is installed.
  Future<void> refresh() async {
    try {
      final facts = await readDeviceFacts();
      switch (checkCapability(facts, requirement)) {
        case NotCapable(:final message):
          _set(AssistantPhase.unsupported, message: message);
          return;
        case Capable():
          break;
      }
      await _registerEngine();
      final installed = await FlutterGemma.listInstalledModels();
      _set(
        installed.isEmpty ? AssistantPhase.notInstalled : AssistantPhase.ready,
      );
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: '$e');
    }
  }

  /// Downloads and installs the model, then loads it.
  ///
  /// Safe to call again: an install that is already on disk is not downloaded
  /// twice.
  Future<void> install() async {
    if (state.value.phase == AssistantPhase.unsupported) return;
    try {
      await _registerEngine();

      // One round trip, before committing the reader to 2.4 GB. Without it a
      // moved file shows up as a bar that climbs for a while and then dies.
      _set(AssistantPhase.checking);
      final chosen = await probe.choose(preferred: _preferred);
      if (chosen.host == null) {
        _set(
          AssistantPhase.failed,
          message: messageForHostStatus(chosen.status),
        );
        return;
      }
      _chosen = chosen.host;

      final token = CancelToken();
      _download = token;
      _lastPercent = -1;
      _set(AssistantPhase.downloading, percent: 0);
      _armStall();

      final installation =
          await FlutterGemma.installModel(
                modelType: ModelType.gemma4,
                fileType: ModelFileType.litertlm,
              )
              .fromNetwork(chosen.host!.url)
              .withCancelToken(token)
              .withProgress(_onProgress)
              .install();

      _stopStall();

      // Trust the file, not the fact that the stream ended.
      final whole = await FlutterGemmaPlugin.instance.modelManager
          .validateModel(installation.spec);
      if (!whole) {
        _set(
          AssistantPhase.failed,
          message:
              'The downloaded file did not check out, so it has not been '
              'used. Trying again will fetch a fresh copy.',
        );
        return;
      }

      await load();
    } on Exception catch (e) {
      _stopStall();
      if (CancelToken.isCancel(e)) {
        await refresh();
        return;
      }
      _set(AssistantPhase.failed, message: _readable(e));
    } finally {
      _download = null;
    }
  }

  /// Checks the phone and, if the model is already installed, loads it now.
  ///
  /// Called at start-up so the first translation is not the load wearing the
  /// translation's clothes: a minute of "Translating…" for what is really the
  /// model starting up.
  Future<void> warmUp() async {
    await refresh();
    if (state.value.phase == AssistantPhase.ready) await load();
  }

  /// Frees the model when the system asks for memory, and when the app is
  /// being torn down.
  void watchLifecycle() => _lifecycle.start();

  late final _lifecycle = _AssistantLifecycle(this);

  /// Stops a download in progress, keeping whatever else is installed.
  void cancelDownload() => _download?.cancel('The reader stopped it.');

  void _onProgress(int percent) {
    // Re-armed on movement only, so a transfer that reports the same number
    // forever is still caught.
    if (percent > _lastPercent) {
      _lastPercent = percent;
      _armStall();
    }
    _set(AssistantPhase.downloading, percent: percent);
  }

  void _armStall() {
    _stall?.cancel();
    _stall = Timer(_stallAfter, () {
      _download?.cancel('The download stopped making progress.');
      _set(
        AssistantPhase.failed,
        message:
            'The download stopped making progress — your connection may have '
            'dropped. Worth trying again.',
      );
    });
  }

  void _stopStall() {
    _stall?.cancel();
    _stall = null;
  }

  /// Uses a model file already on this phone — one another app downloaded, or
  /// one the reader copied over — instead of downloading 2.4 GB again.
  ///
  /// The file is registered where it lies and never copied, so it must stay
  /// readable: if the other app deletes it, the assistant stops working until
  /// it is installed again.
  Future<void> adoptModelFile(String path) async {
    if (state.value.phase == AssistantPhase.unsupported) return;
    try {
      final file = File(path);
      if (!await file.exists()) {
        _set(AssistantPhase.failed, message: 'There is no file at $path.');
        return;
      }
      if (!path.endsWith('.litertlm') && !path.endsWith('.task')) {
        _set(
          AssistantPhase.failed,
          message: 'That is not a model file: it must end in .litertlm.',
        );
        return;
      }
      await _registerEngine();
      _set(AssistantPhase.loading);
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: path.endsWith('.task')
            ? ModelFileType.task
            : ModelFileType.litertlm,
      ).fromFile(path).install();
      await load();
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
    }
  }

  /// Loads the model and keeps it loaded, which is what the ~60 s cold start
  /// buys. Call it once the app knows the assistant is wanted.
  Future<void> load() async {
    if (_model != null) {
      _set(AssistantPhase.ready);
      return;
    }
    try {
      await _registerEngine();
      _set(AssistantPhase.loading);

      // The runtime gives no progress callback for a load, so the bar is time
      // against the last measured load rather than a fiction.
      final started = DateTime.now();
      loadElapsed.value = Duration.zero;
      _ticker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => loadElapsed.value = DateTime.now().difference(started),
      );

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: await _backend(),
      );
      _model = model;

      final took = DateTime.now().difference(started);
      loadEstimate = took;
      settings?.write(_loadMillisKey, '${took.inMilliseconds}');
      _set(AssistantPhase.ready, backend: '${model.activeBackend}');
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
    } finally {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Frees the model from memory, leaving it installed: before another large
  /// model runs, or under memory pressure. The next request loads it again.
  Future<void> unload() async {
    _ticker?.cancel();
    _ticker = null;
    final model = _model;
    _model = null;
    await model?.close();
  }

  /// Deletes the model, giving the reader their storage back.
  Future<void> remove() async {
    try {
      await unload();
      for (final id in await FlutterGemma.listInstalledModels()) {
        await FlutterGemma.uninstallModel(id);
      }
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
      return;
    }
    await refresh();
  }

  /// Answers [request], queued behind any request already running.
  Future<String> ask(AssistantRequest request) {
    final result = _queue.then((_) => _run(request));
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _run(AssistantRequest request) async {
    if (_model == null) await load();
    final model = _model;
    if (model == null) {
      throw StateError('The assistant is not loaded.');
    }

    _set(AssistantPhase.working);
    final chat = await model.createChat(
      systemInstruction: request.systemInstruction,
      temperature: request.temperature,
      // Pure argmax made a phone repeat one character forever (CLAUDE.md).
      topK: 40,
      maxOutputTokens: request.maxOutputTokens,
    );
    final answer = StringBuffer();
    try {
      await chat.addQueryChunk(Message(text: request.prompt, isUser: true));
      await for (final response in chat.generateChatResponseAsync()) {
        switch (response) {
          case TextResponse(:final token):
            answer.write(token);
            // Measure the guard against the visible answer only.
            final keep = detectRunaway(answer.toString());
            if (keep != null) {
              await chat.stopGeneration();
              return cleanOutput(answer.toString().substring(0, keep));
            }
          case ThinkingResponse():
          case FunctionCallResponse():
          case ParallelFunctionCallResponse():
            break;
        }
      }
    } finally {
      await chat.close();
      _set(AssistantPhase.ready, backend: state.value.backend);
    }
    return cleanOutput(answer.toString());
  }

  Future<void> _registerEngine() async {
    if (_engineReady) return;
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
    _engineReady = true;
  }

  /// NPU on Snapdragon, CPU elsewhere; iOS is always CPU (CLAUDE.md).
  Future<PreferredBackend> _backend() async {
    final facts = await readDeviceFacts();
    final backend = selectBackend(
      facts.platform,
      androidHardware: await readAndroidHardware(),
    );
    return switch (backend) {
      InferenceBackend.npu => PreferredBackend.npu,
      InferenceBackend.cpu => PreferredBackend.cpu,
    };
  }

  void _set(
    AssistantPhase phase, {
    int? percent,
    String? message,
    String? backend,
  }) => state.value = AssistantState(
    phase,
    percent: percent,
    message: message,
    backend: backend ?? state.value.backend,
  );
}

/// Listens for the two moments worth unloading a 2.4 GB model.
class _AssistantLifecycle with WidgetsBindingObserver {
  _AssistantLifecycle(this.assistant);

  final Assistant assistant;
  var _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() {
    // The system asking is not a request. Better to reload once than to be
    // killed.
    assistant.unload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Deliberately not `paused`: switching apps and coming back must not cost
    // another minute, and the model is meant to live as long as the process.
    if (state == AppLifecycleState.detached) assistant.unload();
  }
}

String _readable(Object error) => switch (error) {
  DownloadException() => error.error.toUserMessage(),
  _ => '$error',
};
