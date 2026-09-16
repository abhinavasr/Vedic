import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../core/capability.dart';

/// What the phone reports about itself, for the capability gate.
///
/// `physicalRamSize` is megabytes and `freeDiskSize` is bytes; mixing them up
/// is a known trap, so the conversion happens only here.
Future<DeviceFacts> readDeviceFacts([DeviceInfoPlugin? info]) async {
  final device = info ?? DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final android = await device.androidInfo;
    return DeviceFacts(
      platform: DevicePlatform.android,
      isPhysicalDevice: android.isPhysicalDevice,
      ramMb: android.physicalRamSize,
      freeDiskBytes: android.freeDiskSize,
      osMajorVersion: android.version.sdkInt,
    );
  }
  if (Platform.isIOS) {
    final ios = await device.iosInfo;
    return DeviceFacts(
      platform: DevicePlatform.ios,
      isPhysicalDevice: ios.isPhysicalDevice,
      ramMb: ios.physicalRamSize,
      freeDiskBytes: ios.freeDiskSize,
      osMajorVersion: int.tryParse(ios.systemVersion.split('.').first),
    );
  }
  throw UnsupportedError('The assistant runs on Android and iOS only.');
}

/// `Build.HARDWARE`, which says whether this is a Snapdragon and so whether
/// the NPU path exists. Null off Android.
Future<String?> readAndroidHardware([DeviceInfoPlugin? info]) async {
  if (!Platform.isAndroid) return null;
  return (await (info ?? DeviceInfoPlugin()).androidInfo).hardware;
}
