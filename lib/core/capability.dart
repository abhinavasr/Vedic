import 'units.dart';

enum DevicePlatform { android, ios }

/// What the platform layer knows about the phone.
class DeviceFacts {
  const DeviceFacts({
    required this.platform,
    required this.isPhysicalDevice,
    required this.ramMb,
    required this.freeDiskBytes,
    required this.osMajorVersion,
  });

  final DevicePlatform platform;
  final bool isPhysicalDevice;

  /// Total memory in **megabytes** (device_info_plus `physicalRamSize`).
  final int ramMb;

  /// Free storage in **bytes** (device_info_plus `freeDiskSize`).
  final int freeDiskBytes;

  /// Android SDK level, or iOS major version. Null when it could not be read.
  final int? osMajorVersion;
}

/// What a downloadable model needs from the phone.
class ModelRequirement {
  const ModelRequirement({
    required this.displayName,
    required this.downloadBytes,
    required this.minRamMb,
    required this.minFreeDiskBytes,
  });

  /// How refusal messages name the model, e.g. "The assistant".
  final String displayName;
  final int downloadBytes;
  final int minRamMb;

  /// Free space needed before the download starts: the file itself plus the
  /// runtime's compiled-graph cache.
  final int minFreeDiskBytes;
}

enum Refusal {
  simulator,
  osUnknown,
  osTooOld,
  memoryUnknown,
  notEnoughMemory,
  notEnoughStorage,
}

sealed class Capability {
  const Capability();
}

final class Capable extends Capability {
  const Capable();
}

final class NotCapable extends Capability {
  const NotCapable(this.refusal, this.message);

  final Refusal refusal;

  /// Plain-language reason, saying what the user can do where anything helps.
  final String message;
}

/// Android 12, LiteRT-LM's floor (docs/DEVELOPMENT.md).
const int minAndroidSdk = 31;

/// LiteRT-LM requires iOS 16 (docs/DEVELOPMENT.md).
const int minIosMajor = 16;

/// Decides whether [model] may be offered for download on [device].
///
/// Must run before any download prompt. Checks run in a fixed order so the
/// user is told about the most fundamental problem first.
Capability checkCapability(
  DeviceFacts device,
  ModelRequirement model, {
  bool allowSimulator = false,
}) {
  final name = model.displayName;

  // Simulators report the host Mac's memory and disk, so every check below
  // would pass for the wrong reasons.
  //
  // [allowSimulator] is for testing the pipeline itself, where the answer the
  // model gives is the point and the speed it gives it at is meaningless. It
  // is never on in a release: see docs/DEVELOPMENT.md.
  if (!device.isPhysicalDevice && !allowSimulator) {
    return NotCapable(
      Refusal.simulator,
      '$name runs only on a real phone, not on a simulator or emulator.',
    );
  }

  final (minOs, osName) = switch (device.platform) {
    DevicePlatform.android => (minAndroidSdk, 'Android 12'),
    DevicePlatform.ios => (minIosMajor, 'iOS 16'),
  };
  final os = device.osMajorVersion;
  if (os == null) {
    return NotCapable(
      Refusal.osUnknown,
      "Couldn't read this phone's system version, so $name can't be offered.",
    );
  }
  if (os < minOs) {
    return NotCapable(
      Refusal.osTooOld,
      '$name needs $osName or later. Update the phone to use it.',
    );
  }

  if (device.ramMb <= 0) {
    return NotCapable(
      Refusal.memoryUnknown,
      "Couldn't read how much memory this phone has, so $name can't be offered.",
    );
  }
  if (device.ramMb < model.minRamMb) {
    return NotCapable(
      Refusal.notEnoughMemory,
      '$name needs at least ${formatBytes(model.minRamMb * mib)} of memory. '
      'This phone has ${formatBytes(device.ramMb * mib)}.',
    );
  }

  if (device.freeDiskBytes < model.minFreeDiskBytes) {
    final shortfall = model.minFreeDiskBytes - device.freeDiskBytes;
    return NotCapable(
      Refusal.notEnoughStorage,
      '$name needs ${formatBytes(model.minFreeDiskBytes)} of free storage. '
      'Free up another ${formatBytes(shortfall)} to download it.',
    );
  }

  return const Capable();
}
