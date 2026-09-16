import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/backend.dart';
import 'package:vedic/core/capability.dart';
import 'package:vedic/core/model_catalog.dart';
import 'package:vedic/core/units.dart';

DeviceFacts phone({
  DevicePlatform platform = DevicePlatform.android,
  bool physical = true,
  int ramMb = 8 * 1024,
  int freeDiskBytes = 32 * gib,
  int? os = 35,
}) => DeviceFacts(
  platform: platform,
  isPhysicalDevice: physical,
  ramMb: ramMb,
  freeDiskBytes: freeDiskBytes,
  osMajorVersion: os,
);

NotCapable refused(Capability c) {
  expect(c, isA<NotCapable>());
  return c as NotCapable;
}

void main() {
  group('checkCapability', () {
    test('offers the model to a capable phone', () {
      expect(checkCapability(phone(), gemma4E2b.requirement), isA<Capable>());
    });

    test('refuses simulators even when they report plenty of memory', () {
      final r = refused(
        checkCapability(
          phone(physical: false, ramMb: 64 * 1024),
          gemma4E2b.requirement,
        ),
      );
      expect(r.refusal, Refusal.simulator);
    });

    test('requires Android 12', () {
      expect(
        refused(checkCapability(phone(os: 30), gemma4E2b.requirement)).refusal,
        Refusal.osTooOld,
      );
      expect(
        checkCapability(phone(os: 31), gemma4E2b.requirement),
        isA<Capable>(),
      );
    });

    test('requires iOS 16', () {
      final ios = DevicePlatform.ios;
      expect(
        refused(
          checkCapability(phone(platform: ios, os: 15), gemma4E2b.requirement),
        ).refusal,
        Refusal.osTooOld,
      );
      expect(
        checkCapability(phone(platform: ios, os: 16), gemma4E2b.requirement),
        isA<Capable>(),
      );
    });

    test('refuses when the OS version is unknown', () {
      expect(
        refused(checkCapability(phone(os: null), gemma4E2b.requirement))
            .refusal,
        Refusal.osUnknown,
      );
    });

    test('refuses too little memory and names both amounts', () {
      final r = refused(
        checkCapability(phone(ramMb: 2048), gemma4E2b.requirement),
      );
      expect(r.refusal, Refusal.notEnoughMemory);
      expect(r.message, contains('3.0 GB'));
      expect(r.message, contains('2.0 GB'));
    });

    test('memory floor is inclusive', () {
      expect(
        checkCapability(
          phone(ramMb: gemma4E2b.requirement.minRamMb),
          gemma4E2b.requirement,
        ),
        isA<Capable>(),
      );
    });

    test('refuses when memory could not be read', () {
      expect(
        refused(checkCapability(phone(ramMb: 0), gemma4E2b.requirement))
            .refusal,
        Refusal.memoryUnknown,
      );
    });

    test('refuses too little storage and says how much to free', () {
      final r = refused(
        checkCapability(phone(freeDiskBytes: 3 * gib), gemma4E2b.requirement),
      );
      expect(r.refusal, Refusal.notEnoughStorage);
      expect(r.message, contains('Free up another 1.0 GB'));
    });

    test('storage floor is inclusive', () {
      expect(
        checkCapability(
          phone(freeDiskBytes: gemma4E2b.requirement.minFreeDiskBytes),
          gemma4E2b.requirement,
        ),
        isA<Capable>(),
      );
    });

    test('memory is megabytes and storage is bytes', () {
      // A phone with 4 GB of RAM and 4 GB free, each in its own unit.
      final device = phone(ramMb: 4096, freeDiskBytes: 4 * gib);
      expect(checkCapability(device, gemma4E2b.requirement), isA<Capable>());
    });
  });

  group('selectBackend', () {
    test('uses the NPU on Qualcomm Android', () {
      expect(
        selectBackend(DevicePlatform.android, androidHardware: 'qcom'),
        InferenceBackend.npu,
      );
      expect(
        selectBackend(DevicePlatform.android, androidHardware: 'QCOM'),
        InferenceBackend.npu,
      );
    });

    test('uses the CPU everywhere else', () {
      expect(
        selectBackend(DevicePlatform.android, androidHardware: 'mt6789'),
        InferenceBackend.cpu,
      );
      expect(selectBackend(DevicePlatform.android), InferenceBackend.cpu);
      expect(
        selectBackend(DevicePlatform.ios, androidHardware: 'qcom'),
        InferenceBackend.cpu,
      );
    });
  });

  test('formatBytes matches how the docs quote sizes', () {
    expect(formatBytes(2588147712), '2.4 GB');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(300 * mib), '300.0 MB');
  });
}
