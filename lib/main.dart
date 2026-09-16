import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai/assistant.dart';
import 'ai/reading_languages.dart';
import 'ai/store_settings.dart';
import 'app_build.dart';
import 'audio/chant_wiring.dart';
import 'packs/bundled_assets.dart';
import 'packs/pack_store.dart';
import 'packs/trusted_keys.dart';
import 'ui/app.dart';
import 'ui/listen_meaning.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final store = PackStore(
    root: Directory(p.join(support.path, 'packs')),
    trustedKeys: trustedPublisherKeys,
    appBuild: appBuild,
  );
  // The assistant remembers its host and its measured load time; everything
  // else about it is decided fresh each run.
  final settings = StoreAssistantSettings(store);
  Assistant.instance = Assistant(settings: settings);
  ReadingLanguage.instance = ReadingLanguage(settings);
  Assistant.instance.watchLifecycle();
  // Chant playback, where this build has a key for the audio host. Without
  // one there is no chant and nothing says otherwise.
  final chants = chantSource(directory: support);
  if (chants != null) ChantSource.instance = chants;
  runApp(
    VedicApp(
      store: store,
      prepare: () async {
        await store.removeLeftovers();
        await installPacksFromAppBundle(store);
      },
    ),
  );
  // Nothing waits on this: with no model installed it settles on
  // "not installed" and the app never mentions it again.
  unawaited(Assistant.instance.warmUp());
}
