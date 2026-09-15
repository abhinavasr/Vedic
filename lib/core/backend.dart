import 'capability.dart';

enum InferenceBackend { cpu, npu }

/// Picks the LiteRT-LM backend for this phone.
///
/// LiteRT-LM's NPU path is Qualcomm-only, so Snapdragon phones (`Build.HARDWARE`
/// contains "qcom") get the NPU and everything else gets the CPU. iOS is always
/// CPU.
InferenceBackend selectBackend(
  DevicePlatform platform, {
  String? androidHardware,
}) {
  final isQualcomm =
      androidHardware != null && androidHardware.toLowerCase().contains('qcom');
  if (platform == DevicePlatform.android && isQualcomm) {
    return InferenceBackend.npu;
  }
  return InferenceBackend.cpu;
}
