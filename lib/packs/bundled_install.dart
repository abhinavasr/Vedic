import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';
import 'pack_store.dart';

typedef AssetLoader = Future<List<int>> Function(String key);

const _prefix = 'assets/packs/';
const _manifestSuffix = 'manifest.json';

/// Installs every pack under `assets/packs/` that is newer than the installed
/// revision.
///
/// Takes asset keys and a loader rather than an AssetBundle, so it runs
/// without Flutter. See `bundled_assets.dart` for the app's wiring.
Future<List<InstallResult>> installBundledPacks(
  PackStore store, {
  required Iterable<String> assetKeys,
  required AssetLoader load,
}) async {
  final manifests = [
    for (final key in assetKeys)
      if (key.startsWith(_prefix) && key.endsWith('.$_manifestSuffix')) key,
  ]..sort();

  final results = <InstallResult>[];
  for (final key in manifests) {
    final stem = key.substring(0, key.length - _manifestSuffix.length);
    final manifestBytes = await load(key);

    // Unverified read, used only to skip packs that are already installed
    // without copying their payload. install() verifies everything it uses.
    final peek = PackManifest.parse(manifestBytes);
    final installed = store.installedRevision(peek.packId);
    if (installed != null && installed >= peek.revision) {
      results.add(AlreadyInstalled(installed));
      continue;
    }

    await store.tempDirectory.create(recursive: true);
    final staging = await store.tempDirectory.createTemp('bundled-');
    try {
      await File(p.join(staging.path, 'manifest.json'))
          .writeAsBytes(manifestBytes);
      await File(p.join(staging.path, 'manifest.json.sig'))
          .writeAsBytes(await load('${stem}manifest.json.sig'));
      await File(p.join(staging.path, peek.payload.file))
          .writeAsBytes(await load('$stem${peek.payload.file}'));
      results.add(await store.install(staging, origin: PackOrigin.bundled));
    } finally {
      await staging.delete(recursive: true);
    }
  }
  return results;
}
