import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_build.dart';
import 'packs/bundled_assets.dart';
import 'packs/pack_store.dart';
import 'packs/trusted_keys.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final store = PackStore(
    root: Directory(p.join(support.path, 'packs')),
    trustedKeys: trustedPublisherKeys,
    appBuild: appBuild,
  );
  runApp(
    VedicApp(
      store: store,
      prepare: () async {
        await store.removeLeftovers();
        await installPacksFromAppBundle(store);
      },
    ),
  );
}
