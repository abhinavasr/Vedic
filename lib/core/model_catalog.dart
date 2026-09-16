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

String get gemmaModelUrl => '$assistantModelBase/$gemmaModelFileName';

String get gemmaModelFallbackUrl =>
    '$assistantModelFallbackBase/$gemmaModelFileName';

const ModelRequirement gemma4E2bIt = ModelRequirement(
  displayName: 'The assistant',
  downloadBytes: 2588147712,
  // Roadmap §3.5: "~3 GB RAM". From the inherited playbook; not yet measured
  // on this project's devices.
  minRamMb: 3 * 1024,
  // Roadmap §3.5: "4 GB free disk", covering the 2.4 GB file and the ~780 MB
  // compiled-graph cache. Not yet measured on this project's devices.
  minFreeDiskBytes: 4 * gib,
);
