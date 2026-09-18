import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/reading_languages.dart';
import '../core/transliteration.dart';
import '../library/scripture_repository.dart';
import 'brand_header.dart';
import 'home/hero_background.dart';
import 'reader_screens.dart';
import 'search_screen.dart';
import 'theme.dart';

const _heroShadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];

/// Opens a work at its list of chapters.
void _openWork(
  BuildContext context,
  ScriptureRepository repository,
  WorkSummary work,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => WorkScreen(repository: repository, work: work),
  ),
);

/// The shelf: what is installed, where the reader left off, and a way in.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.onOpenSettings,
    this.problem,
  });

  final ScriptureRepository repository;
  final VoidCallback onOpenSettings;

  /// Why bundled content couldn't be installed, if it couldn't.
  final String? problem;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  var _showSanskrit = true;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final works = repository.works();
    final heroHeight = math.max(
      300.0,
      MediaQuery.sizeOf(context).height * 0.34,
    );
    // Every book the reader has opened, most recent first. The store keeps
    // one row per work, so this is already "where I am in each book" — the
    // screen just used to throw all but the first away and show works.first,
    // which meant somebody halfway through the Ṛgveda was told to continue
    // the Gītā.
    final recent = repository.store.recentlyRead(limit: 20);
    final byKey = {
      for (final work in works) '${work.pack.packId}/${work.slug}': work,
    };
    final started = [
      for (final mark in recent) ?byKey['${mark.packId}/${mark.workSlug}'],
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SingleChildScrollView(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: HeroBackground(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SadhanaHeader(onOpenSettings: widget.onOpenSettings),
                        const SizedBox(height: 26),
                        Text(
                          'Scriptures',
                          style: serif(
                            size: 40,
                            color: Colors.white,
                          ).copyWith(shadows: _heroShadow),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 44,
                          height: 2,
                          color: SadhanaColors.gold,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Read, reflect, and return\nto timeless wisdom.',
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.92),
                            shadows: _heroShadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: heroHeight - 34),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SearchBar(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SearchScreen(repository: repository),
                      ),
                    ),
                  ),
                ),
                if (widget.problem case final problem?)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    color: Theme.of(context).colorScheme.errorContainer,
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
                      style: TextStyle(color: SadhanaColors.inkSoft),
                    ),
                  )
                else ...[
                  const SizedBox(height: 20),
                  // One card per book on the go. Nothing started yet means a
                  // single card inviting them into the first book.
                  for (final work in started.isEmpty ? [works.first] : started)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _FeaturedCard(
                        key: ValueKey(
                          'continue-${work.pack.packId}/${work.slug}',
                        ),
                        repository: repository,
                        work: work,
                      ),
                    ),
                  const SizedBox(height: 22),
                  _WorkTiles(repository: repository, works: works),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _VersePreview(
                      repository: repository,
                      showSanskrit: _showSanskrit,
                      onToggle: (value) =>
                          setState(() => _showSanskrit = value),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The book to pick up again: where the reader stopped, and how far in.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    super.key,
    required this.repository,
    required this.work,
  });

  final ScriptureRepository repository;
  final WorkSummary work;

  @override
  Widget build(BuildContext context) {
    final ref = repository.store.lastRead(work.pack.packId, work.slug);
    final sections = repository.sections(work);
    final section = _sectionFor(sections, ref);
    final reached = _reached(section, ref);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: SadhanaColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(work: work),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref == null ? 'START READING' : 'CONTINUE READING',
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: SadhanaColors.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    work.title,
                    style: serif(size: 22, color: SadhanaColors.ink),
                  ),
                  if (section != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _sectionLabel(section),
                      style: const TextStyle(
                        fontSize: 14,
                        color: SadhanaColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (section != null && section.verseCount > 0) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: reached / section.verseCount,
                        minHeight: 5,
                        backgroundColor: SadhanaColors.line,
                        color: SadhanaColors.green,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$reached / ${section.verseCount} verses',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SadhanaColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const ValueKey('library-open'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SadhanaColors.green,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => section == null
                          ? _openWork(context, repository, work)
                          : openSection(
                              context,
                              repository,
                              work,
                              section,
                              atRef: ref,
                            ),
                      child: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static SectionSummary? _sectionFor(
    List<SectionSummary> sections,
    String? ref,
  ) {
    if (sections.isEmpty) return null;
    if (ref == null) return sections.first;
    // Refs read "2.47": the chapter is what comes before the dot.
    final chapter = ref.split('.').first;
    for (final section in sections) {
      if (section.number == chapter) return section;
    }
    return sections.first;
  }

  /// How far into the chapter the reader reached, by the verse's own number.
  static int _reached(SectionSummary? section, String? ref) {
    if (section == null || ref == null) return 0;
    final parts = ref.split('.');
    final verse = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (verse == null) return 0;
    return verse.clamp(0, section.verseCount);
  }

  static String _sectionLabel(SectionSummary section) => section.number == null
      ? section.title ?? 'Other text'
      : 'Chapter ${section.number}'
            '${section.title == null ? '' : '  ·  ${section.title}'}';
}

/// The book's own picture, where the pack carries one.
class _Cover extends StatelessWidget {
  const _Cover({required this.work});

  final WorkSummary work;

  static const _width = 104.0;
  static const _height = 132.0;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(width: _width, height: _height, child: _picture()),
  );

  /// A cover ships with the pack or comes from a partner's server, so both an
  /// asset path and an http URL are accepted. Either way, one that will not
  /// load falls back rather than taking the shelf with it.
  Widget _picture() {
    final url = work.coverUrl;
    if (url == null) return _placeholder();
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    }
    return Image.asset(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF3E7D2), Color(0xFFE8D6B8)],
      ),
    ),
    child: Center(
      child: Text(
        work.titleNative?.characters.first ?? work.title.characters.first,
        style: serif(size: 40, color: SadhanaColors.gold),
      ),
    ),
  );
}

/// One tile per installed work. Nothing is listed that cannot be opened.
class _WorkTiles extends StatelessWidget {
  const _WorkTiles({required this.repository, required this.works});

  final ScriptureRepository repository;
  final List<WorkSummary> works;

  static const _tints = [
    Color(0xFFFBF0DC),
    Color(0xFFFBE7E4),
    Color(0xFFE6F0E2),
    Color(0xFFEDE9F7),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final (index, work) in works.indexed) ...[
          if (index > 0) const SizedBox(width: 12),
          _WorkTile(
            work: work,
            tint: _tints[index % _tints.length],
            onTap: () => _openWork(context, repository, work),
          ),
        ],
      ],
    ),
  );
}

class _WorkTile extends StatelessWidget {
  const _WorkTile({
    required this.work,
    required this.tint,
    required this.onTap,
  });

  final WorkSummary work;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              color: SadhanaColors.gold,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              work.titleNative ?? work.title,
              style: serif(size: 17, color: SadhanaColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              '${work.verseCount} verses',
              style: const TextStyle(
                fontSize: 13,
                color: SadhanaColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Today's verse, in the original or in the reader's language.
class _VersePreview extends StatelessWidget {
  const _VersePreview({
    required this.repository,
    required this.showSanskrit,
    required this.onToggle,
  });

  final ScriptureRepository repository;
  final bool showSanskrit;
  final void Function(bool sanskrit) onToggle;

  @override
  Widget build(BuildContext context) {
    final pick = repository.verseOfTheDay(DateTime.now());
    if (pick == null) return const SizedBox.shrink();
    final verse = pick.verse;
    final translation = verse.translationFor(
      ReadingLanguageScope.of(context).preference,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: SadhanaColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Verse Preview',
                    style: serif(size: 20, color: SadhanaColors.ink),
                  ),
                ),
                _Toggle(showSanskrit: showSanskrit, onToggle: onToggle),
              ],
            ),
            const SizedBox(height: 14),
            if (showSanskrit) ...[
              Text(
                verse.text,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.6,
                  color: SadhanaColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                verse.transliteration ?? devanagariToIast(verse.text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: serif(
                  size: 14,
                  style: FontStyle.italic,
                  color: SadhanaColors.inkSoft,
                ),
              ),
            ] else
              Text(
                translation?.text ??
                    'No translation is installed for this verse yet.',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: SadhanaColors.ink,
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => openVerseSection(context, repository, pick),
                style: TextButton.styleFrom(
                  foregroundColor: SadhanaColors.green,
                ),
                child: Text('Read ${verse.label ?? verse.ref}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.showSanskrit, required this.onToggle});

  final bool showSanskrit;
  final void Function(bool sanskrit) onToggle;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: SadhanaColors.searchFill,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _half('Sanskrit', selected: showSanskrit, onTap: () => onToggle(true)),
        _half('Meaning', selected: !showSanskrit, onTap: () => onToggle(false)),
      ],
    ),
  );

  Widget _half(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => Material(
    color: selected ? SadhanaColors.surface : Colors.transparent,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          key: ValueKey('preview-${label.toLowerCase()}'),
          style: TextStyle(
            fontSize: 13,
            color: selected ? SadhanaColors.ink : SadhanaColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: SadhanaColors.surface,
    shape: const StadiumBorder(side: BorderSide(color: SadhanaColors.line)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.search, color: SadhanaColors.inkSoft, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search scriptures, chapters, verses…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: serif(size: 15, color: SadhanaColors.inkSoft),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
