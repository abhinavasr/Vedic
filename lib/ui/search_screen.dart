import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'reader_screens.dart';
import 'theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final ScriptureRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<VerseOfTheDay> _hits = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) => setState(
    () => _hits = query.trim().length < 2
        ? const []
        : widget.repository.searchVerses(query),
  );

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'Search verses in Devanagari or IAST…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: ListView(
        children: [
          const ListTile(
            enabled: false,
            leading: Icon(Icons.auto_awesome_outlined),
            title: Text('Ask a question'),
            subtitle: Text(
              'Answers from your scriptures, with the verses they come from, '
              "computed on this phone. Needs the assistant download, which isn't "
              'available yet.',
            ),
          ),
          const Divider(),
          if (query.length >= 2 && _hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No verses match "$query".',
                style: const TextStyle(color: SadhanaColors.inkSoft),
              ),
            ),
          for (final hit in _hits)
            ListTile(
              title: Text(
                hit.verse.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${hit.work.title} ${hit.verse.label ?? hit.verse.ref}',
              ),
              onTap: () => openVerseSection(context, widget.repository, hit),
            ),
        ],
      ),
    );
  }
}
