import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'reader_screens.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.repository, this.problem});

  final ScriptureRepository repository;

  /// Why bundled content couldn't be installed, if it couldn't.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final works = repository.works();
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        children: [
          if (problem case final problem?)
            Card(
              margin: const EdgeInsets.all(16),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text("Couldn't install bundled scripture"),
                subtitle: Text(problem),
              ),
            ),
          if (works.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No scripture installed yet.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final work in works)
            ListTile(
              title: Text(
                work.titleNative ?? work.title,
                style: theme.textTheme.titleLarge,
              ),
              subtitle: Text('${work.title} · ${work.verseCount} verses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      WorkScreen(repository: repository, work: work),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
