import 'capability.dart';
import 'units.dart';

/// The generic LiteRT-LM build. The `-gpu` file is a WebGPU build that fails on
/// Android, and the per-SoC files failed to create an engine (CLAUDE.md).
const String gemmaModelFileName = 'gemma-4-E2B-it.litertlm';

/// Where model weights are downloaded from. Switching hosts is a build flag,
/// not a release (docs/DEVELOPMENT.md).
const String assistantModelBase = String.fromEnvironment(
  'ASSISTANT_MODEL_BASE',
  defaultValue: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main',
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

/// Overridable so a test build can point at a small model. The file name is
/// part of the model's identity on disk, so changing it installs a different
/// model rather than confusing this one.
const String assistantModelFile = String.fromEnvironment(
  'ASSISTANT_MODEL_FILE',
  defaultValue: gemmaModelFileName,
);

/// Which family the runtime should treat the file as: `gemma4` for the real
/// model, and whatever a test build points at otherwise. Wrong values here
/// fail at load with "Model may be invalid", which is true only of the pairing.
const String assistantModelFamily = String.fromEnvironment(
  'ASSISTANT_MODEL_FAMILY',
  defaultValue: 'gemma4',
);

/// The download's size, for the prompt that asks before spending it.
const int assistantModelBytes = int.fromEnvironment(
  'ASSISTANT_MODEL_BYTES',
  defaultValue: 2588147712,
);

/// Lets a test build run the assistant on a simulator, where the answer is
/// the point and the speed is meaningless. Never on in a release.
const bool allowSimulatorAi = bool.fromEnvironment('ASSISTANT_ALLOW_SIMULATOR');

String get gemmaModelUrl => '$assistantModelBase/$assistantModelFile';

String get gemmaModelFallbackUrl =>
    '$assistantModelFallbackBase/$assistantModelFile';

const ModelRequirement gemma4E2bIt = ModelRequirement(
  displayName: 'The assistant',
  downloadBytes: assistantModelBytes,
  // Roadmap §3.5: "~3 GB RAM". From the inherited playbook; not yet measured
  // on this project's devices.
  minRamMb: 3 * 1024,
  // Roadmap §3.5: "4 GB free disk", covering the 2.4 GB file and the ~780 MB
  // compiled-graph cache. Not yet measured on this project's devices.
  minFreeDiskBytes: 4 * gib,
);
