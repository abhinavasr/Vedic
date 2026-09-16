import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'bookmarks_screen.dart';
import 'home/home_screen.dart';
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
