import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import '../ai/reading_languages.dart';
import 'bookmarks_screen.dart';
import 'home/home_screen.dart';
import 'reader_screens.dart';
import 'library_screen.dart';
import 'meditation_screen.dart';
import 'simple_screens.dart';

class SadhanaShell extends StatefulWidget {
  const SadhanaShell({super.key, required this.repository, this.problem});

  final ScriptureRepository repository;
  final String? problem;

  @override
  State<SadhanaShell> createState() => _SadhanaShellState();
}

class _SadhanaShellState extends State<SadhanaShell> {
  var _tab = 0;

  /// Counts visits to the bookmarks tab, so it re-reads the list when opened
  /// rather than showing what was there when the app started.
  var _bookmarkVisits = 0;

  void _open(int tab) => setState(() {
    _tab = tab;
    if (tab == 2) _bookmarkVisits++;
  });

  /// Opens the reader where the reader left off, with the chant switched on.
  ///
  /// Someone who taps Listen has said what they want to hear, so the mix is
  /// set for them rather than left for them to find — the meaning stays on
  /// beside it, which is what the tile has always promised.
  void _openChants() {
    final reading = ReadingLanguageScope.of(context);
    reading.mix = reading.mix.with_(chant: true);
    final work = widget.repository.works().firstOrNull;
    if (work == null) return;
    final mark = widget.repository.store.lastRead(work.pack.packId, work.slug);
    final section = mark == null
        ? widget.repository.sections(work).firstOrNull
        : widget.repository.sections(work).where(
            (s) => s.number == mark.split('.').first,
          ).firstOrNull ??
              widget.repository.sections(work).firstOrNull;
    if (section == null) return;
    openSection(context, widget.repository, work, section, atRef: mark);
  }

  void _openSettings() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        HomeScreen(
          repository: widget.repository,
          problem: widget.problem,
          onOpenLibrary: () => _open(1),
          onOpenMeditation: () => _open(3),
          onOpenSettings: _openSettings,
          onOpenChants: _openChants,
        ),
        LibraryScreen(
          repository: widget.repository,
          problem: widget.problem,
          onOpenSettings: _openSettings,
        ),
        // Where the bookmark button leads. It has been in the reader from the
        // start with nowhere to go, which made keeping a verse a way of
        // losing it.
        BookmarksScreen(
          repository: widget.repository,
          onOpenSettings: _openSettings,
          revision: _bookmarkVisits,
        ),
        const MeditationScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _open,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book_rounded),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border),
          selectedIcon: Icon(Icons.bookmark),
          label: 'Bookmarks',
        ),
        NavigationDestination(
          icon: Icon(Icons.self_improvement),
          selectedIcon: Icon(Icons.self_improvement),
          label: 'Meditation',
        ),
      ],
    ),
  );
}
