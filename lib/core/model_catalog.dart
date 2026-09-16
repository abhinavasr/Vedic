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

String get gemmaModelUrl => '$assistantModelBase/$gemmaModelFileName';

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
