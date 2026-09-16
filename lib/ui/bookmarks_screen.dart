import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/reading_languages.dart';
import '../library/scripture_repository.dart';
import '../packs/pack_store.dart';
import 'brand_header.dart';
import 'home/hero_background.dart';
import 'reader_screens.dart';
import 'theme.dart';

/// Every verse the reader has kept.
///
/// The bookmark button has been in the reader all along with nowhere to lead:
/// a verse could be kept and then never found again. There is no limit on how
/// many — they are a list, newest first, and each one goes back to the verse.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.repository,
    required this.onOpenSettings,
    this.revision = 0,
  });

  final ScriptureRepository repository;
  final VoidCallback onOpenSettings;

  /// Bumped by the shell every time this tab is opened.
  ///
  /// The tabs are an [IndexedStack], so this screen is built once and kept:
  /// without a nudge, a verse kept in the reader would not appear here until
  /// the app was restarted.
  final int revision;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen>
    with WidgetsBindingObserver {
  late var _marks = widget.repository.store.bookmarks();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(BookmarksScreen old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The list is a tab, not a route, so it is still here when the reader comes
  /// back from keeping a verse. Reading it again on every visit is cheap.
  void _refresh() =>
      setState(() => _marks = widget.repository.store.bookmarks());

  @override
  Widget build(BuildContext context) {
    // Registers this screen with the reading language: what a kept verse says
    // should follow the same setting as everywhere else.
    ReadingLanguageScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  _marks.isEmpty ? 'Bookmarks' : 'Bookmarks · ${_marks.length}',
                  style: serif(size: 26, color: SadhanaColors.ink),
                ),
              ),
            ),
            if (_marks.isEmpty)
              const SliverToBoxAdapter(child: _NothingKept())
            else
              SliverList.builder(
                itemCount: _marks.length,
                itemBuilder: (context, i) => _BookmarkRow(
                  repository: widget.repository,
                  mark: _marks[i],
                  onChanged: _refresh,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _NothingKept extends StatelessWidget {
  const _NothingKept();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.bookmark_border, size: 40, color: SadhanaColors.inkSoft),
        SizedBox(height: 12),
        Text(
          'Nothing kept yet.',
          style: TextStyle(fontSize: 17, color: SadhanaColors.ink),
        ),
        SizedBox(height: 6),
        Text(
          'While you are reading, the bookmark at the top of the screen keeps '
          'a verse. Keep as many as you like — they all come back here.',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: SadhanaColors.inkSoft,
          ),
        ),
      ],
    ),
  );
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({
    required this.repository,
    required this.mark,
    required this.onChanged,
  });

  final ScriptureRepository repository;
  final ReadingMark mark;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final work = repository
        .works()
        .where((w) => w.pack.packId == mark.packId && w.slug == mark.workSlug)
        .firstOrNull;
    if (work == null) return const SizedBox.shrink();
    final section = _sectionOf(work);
    final verse = section == null
        ? null
        : repository
              .verses(work, section)
              .where((v) => v.ref == mark.ref)
              .firstOrNull;
    final meaning = verse?.translationFor(
      ReadingLanguageScope.of(context).preference,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: SadhanaColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: section == null
              ? null
              : () => openSection(
                  context,
                  repository,
                  work,
                  section,
                  atRef: mark.ref,
                  // Going to a kept verse is a visit too: it must not move
                  // where the reader had got to in the book.
                  visiting: true,
                ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${work.title}  ·  ${verse?.label ?? mark.ref}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: SadhanaColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (verse != null)
                        Text(
                          verse.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.5,
                            color: SadhanaColors.ink,
                          ),
                        ),
                      if (meaning != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          meaning.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: SadhanaColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove bookmark',
                  icon: const Icon(Icons.bookmark, color: SadhanaColors.gold),
                  onPressed: () {
                    repository.store.toggleBookmark(
                      packId: mark.packId,
                      workSlug: mark.workSlug,
                      ref: mark.ref,
                    );
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SectionSummary? _sectionOf(WorkSummary work) {
    final chapter = mark.ref.split('.').first;
    for (final section in repository.sections(work)) {
      if (section.number == chapter) return section;
    }
    return null;
  }
}
