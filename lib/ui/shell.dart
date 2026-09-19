import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'bookmarks_screen.dart';
import 'home/home_screen.dart';
import 'listen_screen.dart';
import 'panchang_screen.dart';
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

  /// Opens the listening player where the listener left off.
  ///
  /// A destination of its own rather than the reader with a chip set: nothing
  /// to read, nothing to scroll, and it keeps going by itself.
  void _openChants() {
    final work = widget.repository.works().firstOrNull;
    if (work == null) return;
    // Where listening left off, which is its own place in the book: someone
    // may be reading one chapter and listening to another.
    final mark =
        widget.repository.store.setting(
          'listen.at/${work.pack.packId}/${work.slug}',
        ) ??
        widget.repository.store.lastRead(work.pack.packId, work.slug);
    // Only sections with verses in them: a work's front matter has no chapter
    // number, so matching on a null mark landed there — a chapter called
    // "Other" holding nothing, and a player reporting "1 of 0".
    final sections = [
      for (final section in widget.repository.sections(work))
        if (section.verseCount > 0) section,
    ];
    final chapter = mark?.split('.').first;
    final section =
        (chapter == null
            ? null
            : sections.where((s) => s.number == chapter).firstOrNull) ??
        sections.firstOrNull;
    if (section == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenScreen(
          repository: widget.repository,
          work: work,
          section: section,
          startAt: mark,
        ),
      ),
    );
  }

  /// Meditation, which lost its tab but not its place.
  void _openMeditation() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MeditationScreen()));

  /// The day's panchang, computed here rather than fetched.
  void _openPanchang() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PanchangScreen(onOpenSettings: _openSettings),
    ),
  );

  void _openSettings() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => ProfileScreen(repository: widget.repository)));

  @override
  Widget build(BuildContext context) => PopScope(
    // Back goes Home before it goes anywhere else. Leaving the app from the
    // middle of it — three tabs deep, having pressed nothing but Back — is a
    // way to lose your place, and every Android app worth using returns you to
    // its first screen first.
    canPop: _tab == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _open(0);
    },
    child: Scaffold(
      body: IndexedStack(
      index: _tab,
      children: [
        HomeScreen(
          repository: widget.repository,
          problem: widget.problem,
          onOpenLibrary: () => _open(1),
          onOpenMeditation: _openMeditation,
          onOpenSettings: _openSettings,
          onOpenChants: _openChants,
          onOpenPanchang: _openPanchang,
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
      ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _open,
        // Three, not four. Meditation had a tab and a tile on the home
        // screen, and the tab was the one nobody needed: it is a thing you go
        // and do, not a place you keep returning to.
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
        ],
      ),
    ),
  );
}
