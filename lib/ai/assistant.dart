import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../core/backend.dart';
import '../core/capability.dart';
import '../core/model_catalog.dart';
import '../core/output_hygiene.dart';
import 'device_facts.dart';

// The on-device assistant: one model per process, one request at a time.
// Everything here degrades to absent — with no model installed the app simply
// offers to install one.

enum AssistantPhase {
  /// Nothing checked yet.
  unknown,

  /// This phone cannot run the model; [AssistantState.message] says why.
  unsupported,
  notInstalled,
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

class Assistant {
  Assistant({this.requirement = gemma4E2bIt, String? modelUrl})
    : modelUrl = modelUrl ?? gemmaModelUrl;

  /// The app's assistant. Replaceable in tests.
  static Assistant instance = Assistant();

  final ModelRequirement requirement;
  final String modelUrl;

  final state = ValueNotifier<AssistantState>(
    const AssistantState(AssistantPhase.unknown),
  );

  var _engineReady = false;
  InferenceModel? _model;

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
      _set(AssistantPhase.downloading, percent: 0);
      await FlutterGemma.installModel(
            modelType: ModelType.gemma4,
            fileType: ModelFileType.litertlm,
          )
          .fromNetwork(modelUrl)
          .withProgress(
            (percent) => _set(AssistantPhase.downloading, percent: percent),
          )
          .install();
      await load();
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
    }
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
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: await _backend(),
      );
      _model = model;
      _set(AssistantPhase.ready, backend: '${model.activeBackend}');
    } on Exception catch (e) {
      _set(AssistantPhase.failed, message: _readable(e));
    }
  }

  /// Frees the model from memory, leaving it installed: before another large
  /// model runs, or under memory pressure. The next request loads it again.
  Future<void> unload() async {
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

String _readable(Object error) => switch (error) {
  DownloadException() => error.error.toUserMessage(),
  _ => '$error',
};
