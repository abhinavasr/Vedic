import 'package:flutter/services.dart';

import 'bundled_install.dart';
import 'pack_store.dart';

/// Installs the packs shipped in the app bundle under `assets/packs/`.
Future<List<InstallResult>> installPacksFromAppBundle(
  PackStore store, {
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  return installBundledPacks(
    store,
    assetKeys: manifest.listAssets(),
    load: (key) async {
      final data = await assets.load(key);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    },
  );
}
