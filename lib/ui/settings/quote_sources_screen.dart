import 'package:flutter/material.dart';

import '../../library/quote_sources.dart';
import '../../library/scripture_repository.dart';
import '../theme.dart';

/// Choosing which books the morning verse is drawn from.
class QuoteSourcesScreen extends StatefulWidget {
  const QuoteSourcesScreen({super.key, required this.repository});

  final ScriptureRepository repository;

  @override
  State<QuoteSourcesScreen> createState() => _QuoteSourcesScreenState();
}

class _QuoteSourcesScreenState extends State<QuoteSourcesScreen> {
  late final _sources = QuoteSources(widget.repository.store);

  @override
  Widget build(BuildContext context) {
    final works = widget.repository.works();
    final on = [for (final work in works) if (_sources.includes(work)) work];

    return Scaffold(
      appBar: AppBar(title: const Text('Verse of the day')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              on.isEmpty
                  ? 'No book is selected, so there is no verse of the day.'
                  : 'Drawn each morning from '
                        '${on.length == works.length ? 'every book' : on.length == 1 ? 'one book' : '${on.length} books'}.',
              style: const TextStyle(
                fontSize: 14,
                color: SadhanaColors.inkSoft,
              ),
            ),
          ),
          for (final work in works)
            SwitchListTile(
              key: ValueKey('quote-source-${work.slug}'),
              value: _sources.includes(work),
              onChanged: (value) => setState(
                () => _sources.set(work, on: value, all: works),
              ),
              title: Text(work.title),
              subtitle: Text(
                '${work.verseCount} verses',
                style: const TextStyle(color: SadhanaColors.inkSoft),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Text(
              'A verse is drawn by length, so a long book is offered more '
              'often than a short one. Marking a passage while reading adds '
              'its book here.',
              style: TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
