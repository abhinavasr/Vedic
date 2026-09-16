import 'package:flutter/material.dart';

import '../ai/reading_languages.dart';

import '../library/scripture_repository.dart';
import '../packs/pack_store.dart';
import 'shell.dart';
import 'theme.dart';

class VedicApp extends StatefulWidget {
  const VedicApp({super.key, required this.store, required this.prepare});

  final PackStore store;

  /// Installs bundled content. The app opens even if this fails, showing
  /// whatever is already installed.
  final Future<void> Function() prepare;

  @override
  State<VedicApp> createState() => _VedicAppState();
}

class _VedicAppState extends State<VedicApp> {
  late final Future<void> _ready = widget.prepare();

  @override
  Widget build(BuildContext context) => ReadingLanguageScope(
    language: ReadingLanguage.instance,
    child: MaterialApp(
      title: 'Sadhana',
      theme: sadhanaTheme(),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _Preparing();
          }
          return SadhanaShell(
            repository: ScriptureRepository(widget.store),
            problem: snapshot.hasError ? '${snapshot.error}' : null,
          );
        },
      ),
    ),
  );
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: SadhanaColors.green),
          SizedBox(height: 16),
          Text('Preparing scripture…'),
        ],
      ),
    ),
  );
}
