import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../core/backend.dart';
import '../core/capability.dart';
import '../core/model_catalog.dart';
import '../core/output_hygiene.dart';
import '../core/thinking.dart';
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
    this.maxChars = 6000,
    this.thinking = false,
  });

  final String systemInstruction;
  final String prompt;

  /// The ceiling on generated tokens. With [thinking] on it has to cover the
  /// reasoning too: they draw on the same budget.
  final int maxOutputTokens;
  final double temperature;

  /// How long an answer may get before it is treated as a loop. Sized to the
  /// task, because a caption and an explanation are not the same length.
  final int maxChars;

  /// Whether the model reasons before answering. Slower, and better on a
  /// dense verse.
  final bool thinking;
}

/// An answer as it arrives: both fields accumulate, so each chunk is the whole
/// of what there is so far rather than a delta.
@immutable
class AssistantChunk {
  const AssistantChunk({required this.answer, required this.thinking});

  /// The answer so far, with any reasoning already removed.
  final String answer;

  /// The reasoning so far. Empty unless the request asked for it.
  final String thinking;
}

/// Where the assistant remembers its few settings between runs.
abstract class AssistantSettings {
  String? read(String key);

  void write(String key, String? value);
}

class Assistant {
  Assistant({this.probe = const HostProbe(), this.settings}) {
    _model = modelChoiceById(settings?.read(_modelKey));
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
  static const _modelKey = 'assistant.model';
  static const _loadMillisKey = 'assistant.loadMillis';

  /// A download that has made no progress for this long is stuck, whatever the
  /// transfer layer still believes.
  static const _stallAfter = Duration(seconds: 90);

  final HostProbe probe;
  final AssistantSettings? settings;

  late ModelChoice _model;

  /// Which model the reader picked. Changing it does not touch what is
  /// already installed; the new one is downloaded when they ask for it.
  ModelChoice get model => _model;

  /// Records the choice. The caller decides when to look at the phone again:
  /// a setter that quietly starts asynchronous work is a setter that fires in
  /// the middle of a test.
  set model(ModelChoice choice) {
    if (choice.id == _model.id) return;
    _model = choice;
    settings?.write(_modelKey, choice.id);
  }

  ModelRequirement get requirement => _model.requirement;

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
  InferenceModel? _loaded;
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
      switch (checkCapability(
        facts,
        requirement,
        allowSimulator: allowSimulatorAi,
      )) {
        case NotCapable(:final message):
          _set(AssistantPhase.unsupported, message: message);
          return;
        case Capable():
          break;
      }
      await _registerEngine();
      // This model, not any model: the reader can have installed one and then
      // picked another. The runtime names an installed model by its file in
      // some places and by the file without its extension in others, so both
      // count as a match.
      final installed = await FlutterGemma.listInstalledModels();
      _set(
        _installedName(installed) == null
            ? AssistantPhase.notInstalled
            : AssistantPhase.ready,
      );
    } on UnsupportedError catch (e) {
      // Not a phone at all. The feature is absent rather than broken.
      _set(AssistantPhase.unsupported, message: e.message ?? '$e');
    } on Object catch (e) {
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
      final chosen = await probe.choose(model: _model, preferred: _preferred);
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
                modelType: modelFamily(_model.family),
                fileType: ModelFileType.litertlm,
              )
              .fromNetwork(chosen.host!.urlFor(_model))
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
    } on Object catch (e) {
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
        modelType: modelFamily(_model.family),
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
    if (_loaded != null) {
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
      _loaded = model;

      final took = DateTime.now().difference(started);
      loadEstimate = took;
      settings?.write(_loadMillisKey, '${took.inMilliseconds}');
      _set(AssistantPhase.ready, backend: '${model.activeBackend}');
    } on Object catch (e) {
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
    final model = _loaded;
    _loaded = null;
    await model?.close();
  }

  /// Deletes the model in use, giving the reader their storage back.
  Future<void> remove() async {
    try {
      await unload();
      final name = _installedName(await FlutterGemma.listInstalledModels());
      if (name != null) await FlutterGemma.uninstallModel(name);
    } on Object catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
      return;
    }
    await refresh();
  }

  /// Answers [request] as it is written, queued behind anything already
  /// running.
  ///
  /// The stream is returned at once and the work starts when its turn comes,
  /// so a caller can show "waiting" without holding a future that looks
  /// identical to a stalled one.
  Stream<AssistantChunk> stream(AssistantRequest request) {
    final out = StreamController<AssistantChunk>();
    _queue = _queue
        .then((_) => _run(request, out))
        // One failed generation must not poison every later one. The error
        // has already reached the caller through the stream.
        .catchError((Object _) {})
        .whenComplete(out.close);
    return out.stream;
  }

  /// Answers [request] in one piece, for callers with nothing to show until
  /// the answer is whole.
  Future<String> ask(AssistantRequest request) async {
    var answer = '';
    await for (final chunk in stream(request)) {
      answer = chunk.answer;
    }
    return answer;
  }

  Future<void> _run(
    AssistantRequest request,
    StreamController<AssistantChunk> out,
  ) async {
    try {
      if (_loaded == null) await load();
      final model = _loaded;
      if (model == null) {
        throw StateError('The assistant is not loaded.');
      }

      _set(AssistantPhase.working);
      final chat = await model.createChat(
        systemInstruction: request.systemInstruction,
        temperature: request.temperature,
        // Pure argmax made a phone repeat one character forever (CLAUDE.md).
        topK: 40,
        randomSeed: 1,
        maxOutputTokens: request.maxOutputTokens,
        isThinking: request.thinking,
        modelType: modelFamily(_model.family),
      );
      final raw = StringBuffer();
      final thinking = StringBuffer();
      try {
        await chat.addQueryChunk(Message(text: request.prompt, isUser: true));
        await for (final response in chat.generateChatResponseAsync()) {
          switch (response) {
            case TextResponse(:final token):
              raw.write(token);
            case ThinkingResponse(:final content):
              thinking.write(content);
            case FunctionCallResponse():
            case ParallelFunctionCallResponse():
              continue;
          }

          // The guard is measured against the visible answer, never the
          // reasoning: reasoning legitimately repeats itself, and a model that
          // deliberated for 400 characters would be cut off before writing a
          // word of the answer.
          final visible = cleanOutput(withoutThinking(raw.toString()));
          final keep = detectRunaway(visible, maxChars: request.maxChars);
          if (keep != null) {
            await chat.stopGeneration();
            out.add(
              AssistantChunk(
                answer: visible.substring(0, keep),
                thinking: thinking.toString().trim(),
              ),
            );
            return;
          }
          if (visible.isNotEmpty || thinking.isNotEmpty) {
            out.add(
              AssistantChunk(
                answer: visible,
                thinking: thinking.toString().trim(),
              ),
            );
          }
        }
        out.add(
          AssistantChunk(
            answer: cleanOutput(withoutThinking(raw.toString())),
            thinking: thinking.toString().trim(),
          ),
        );
      } finally {
        await chat.close();
        _set(AssistantPhase.ready, backend: state.value.backend);
      }
    } on Object catch (e, trace) {
      out.addError(e, trace);
    }
  }

  /// What the runtime calls this model, if it has it at all.
  String? _installedName(List<String> installed) {
    for (final id in installed) {
      if (id == _model.fileName || id == _model.modelId) return id;
    }
    return null;
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

/// Which family the runtime treats the installed file as.
///
/// The pairing matters: hand a file to the wrong family and it fails to load
/// with "Model may be invalid", which is true only of the pairing.
ModelType modelFamily(String family) => switch (family) {
  'gemma4' => ModelType.gemma4,
  'gemmaIt' => ModelType.gemmaIt,
  'qwen3' => ModelType.qwen3,
  'qwen' => ModelType.qwen,
  'deepSeek' => ModelType.deepSeek,
  'llama' => ModelType.llama,
  'phi' => ModelType.phi,
  final other => throw ArgumentError('Unknown model family: $other'),
};

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
