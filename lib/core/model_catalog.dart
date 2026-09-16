import 'capability.dart';
import 'units.dart';

// Which models the reader may install, and where they come from.

/// Where model weights are downloaded from. Switching hosts is a build flag,
/// not a release (docs/DEVELOPMENT.md).
///
/// Hugging Face first, because it costs nothing and it works.
const String assistantModelBase = String.fromEnvironment(
  'ASSISTANT_MODEL_BASE',
  defaultValue: 'https://huggingface.co',
);

/// Tried when Hugging Face cannot serve the file, and offered outright to
/// anyone whose download is crawling.
///
/// A rename, a rate limit or a licence gate on their side then costs a slower
/// download rather than the whole feature.
const String assistantModelFallbackBase = String.fromEnvironment(
  'ASSISTANT_MODEL_FALLBACK_BASE',
  defaultValue: 'https://batiyao.com/models',
);

/// Lets a test build run the assistant on a simulator, where the answer is
/// the point and the speed is meaningless. Never on in a release.
const bool allowSimulatorAi = bool.fromEnvironment('ASSISTANT_ALLOW_SIMULATOR');

/// A model the reader can install.
class ModelChoice {
  const ModelChoice({
    required this.id,
    required this.name,
    required this.summary,
    required this.repoPath,
    required this.fileName,
    required this.family,
    required this.requirement,
  });

  /// Stable, and stored: it is how a choice survives a restart.
  final String id;

  /// As the picker names it.
  final String name;

  /// One line on what it is good for, honest about the trade.
  final String summary;

  /// The Hugging Face path the file sits at, without the host.
  final String repoPath;

  /// The file's own name, which is also its identity on disk: two models must
  /// never share one, or installing the second looks like the first.
  final String fileName;

  /// Which family the runtime treats the file as. The wrong value here fails
  /// at load with "Model may be invalid", which is true only of the pairing.
  final String family;

  final ModelRequirement requirement;

  int get downloadBytes => requirement.downloadBytes;

  /// How the runtime names it once installed: the file without its extension.
  String get modelId => fileName.substring(0, fileName.lastIndexOf('.'));

  String get url => '$assistantModelBase/$repoPath/$fileName';

  /// The mirror serves files by name, flat.
  String get mirrorUrl => '$assistantModelFallbackBase/$fileName';
}

/// The generic LiteRT-LM build. The `-gpu` file is a WebGPU build that fails
/// on Android, and the per-SoC files failed to create an engine (CLAUDE.md).
const ModelChoice gemma4E2b = ModelChoice(
  id: 'gemma-4-e2b',
  name: 'Gemma 4 E2B',
  summary:
      'The best translations this app can make on a phone. A large download, '
      'and it needs a recent handset.',
  repoPath: 'litert-community/gemma-4-E2B-it-litert-lm/resolve/main',
  fileName: 'gemma-4-E2B-it.litertlm',
  family: 'gemma4',
  requirement: ModelRequirement(
    displayName: 'The assistant',
    downloadBytes: 2588147712,
    // Roadmap §3.5: "~3 GB RAM". From the inherited playbook; not yet
    // measured on this project's devices.
    minRamMb: 3 * 1024,
    // Roadmap §3.5: "4 GB free disk", covering the 2.4 GB file and the
    // ~780 MB compiled-graph cache.
    minFreeDiskBytes: 4 * gib,
  ),
);

/// Small enough for a modest phone, and noticeably weaker: it was the model
/// that answered a verse with the verse spelled out in Latin letters
/// (docs/ON_DEVICE_AI.md).
const ModelChoice qwen3_06b = ModelChoice(
  id: 'qwen3-0.6b',
  name: 'Qwen3 0.6B',
  summary:
      'Seven times smaller and much faster, and its translations are rougher. '
      'For a phone that cannot hold the larger one.',
  repoPath: 'litert-community/Qwen3-0.6B-int4/resolve/main',
  fileName: 'qwen3_0.6b_q4_block32_ekv1280.litertlm',
  family: 'qwen3',
  requirement: ModelRequirement(
    displayName: 'The assistant',
    downloadBytes: 347251840,
    minRamMb: 2 * 1024,
    minFreeDiskBytes: 1 * gib,
  ),
);

/// Best first. The default is the first entry.
const List<ModelChoice> assistantModels = [gemma4E2b, qwen3_06b];

ModelChoice modelChoiceById(String? id) {
  for (final model in assistantModels) {
    if (model.id == id) return model;
  }
  return assistantModels.first;
}
