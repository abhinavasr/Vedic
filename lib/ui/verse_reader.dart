import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/assistant.dart';
import '../ai/translation.dart';
import '../core/model_catalog.dart';
import '../core/transliteration.dart';
import '../library/scripture_repository.dart';
import '../packs/pack_store.dart';
import 'ai/assistant_screen.dart';
import 'home/hero_painter.dart';
import 'simple_screens.dart';
import 'theme.dart';

enum _Show { sanskrit, meaning, both }

/// Reads a chapter one verse at a time: Sanskrit, its meaning, or both.
class VerseReaderScreen extends StatefulWidget {
  const VerseReaderScreen({
    super.key,
    required this.repository,
    required this.work,
    required this.section,
    this.initialRef,
  });

  final ScriptureRepository repository;
  final WorkSummary work;
  final SectionSummary section;

  /// The verse to open at, e.g. from the verse of the day.
  final String? initialRef;

  @override
  State<VerseReaderScreen> createState() => _VerseReaderScreenState();
}

class _VerseReaderScreenState extends State<VerseReaderScreen> {
  late var _verses = widget.repository.verses(widget.work, widget.section);
  late final PageController _pages;
  var _show = _Show.both;
  var _index = 0;
  var _bookmarked = false;

  /// The verse being translated on the phone, if any.
  String? _translating;

  @override
  void initState() {
    super.initState();
    final wanted = widget.initialRef;
    final at = wanted == null
        ? -1
        : _verses.indexWhere((verse) => verse.ref == wanted);
    _index = at < 0 ? 0 : at;
    _pages = PageController(initialPage: _index);
    _syncVerse();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  PassageView? get _verse => _verses.isEmpty ? null : _verses[_index];

  /// Remembers where the reader is, and whether this verse is bookmarked.
  void _syncVerse() {
    final verse = _verse;
    if (verse == null) return;
    final pack = widget.work.pack.packId;
    widget.repository.store.saveLastRead(
      packId: pack,
      workSlug: widget.work.slug,
      ref: verse.ref,
    );
    _bookmarked = widget.repository.store.isBookmarked(
      pack,
      widget.work.slug,
      verse.ref,
    );
  }

  void _goTo(int index) {
    if (index < 0 || index >= _verses.length) return;
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _toggleBookmark() {
    final verse = _verse;
    if (verse == null) return;
    final now = widget.repository.store.toggleBookmark(
      packId: widget.work.pack.packId,
      workSlug: widget.work.slug,
      ref: verse.ref,
    );
    setState(() => _bookmarked = now);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          now ? 'Bookmarked ${verse.label ?? verse.ref}' : 'Bookmark removed',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Translates a verse on this phone, once the reader has asked for it.
  ///
  /// With no model installed this leads to the setup screen instead: the
  /// download is large and never starts on its own.
  Future<void> _translate(PassageView verse, TargetLanguage language) async {
    final assistant = Assistant.instance;
    if (assistant.state.value.phase == AssistantPhase.unknown) {
      await assistant.refresh();
    }
    if (!mounted) return;
    if (!assistant.state.value.canAnswer) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen()));
      return;
    }

    setState(() => _translating = verse.ref);
    try {
      final text = await translateVerse(
        assistant,
        verse: verse.text,
        language: language,
      );
      widget.repository.store.saveLocalTranslation(
        LocalTranslation(
          packId: widget.work.pack.packId,
          workSlug: widget.work.slug,
          ref: verse.ref,
          language: language.code,
          text: text,
          model: gemmaModelFileName,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) return;
      setState(
        () => _verses = widget.repository.verses(widget.work, widget.section),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is TranslationRejected
                ? e.message
                : 'The translation did not finish. Try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _translating = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final chapter = section.number == null
        ? section.title ?? 'Other text'
        : 'Chapter ${section.number}'
              '${section.title == null ? '' : '  ·  ${section.title}'}';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 320,
              child: CustomPaint(
                painter: HeroPainter(
                  fadeTo: SadhanaColors.background,
                  light: true,
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _toolbar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.work.titleNative ?? widget.work.title,
                          style: serif(size: 34, color: SadhanaColors.ink),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 44,
                          height: 2,
                          color: SadhanaColors.gold,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          chapter,
                          style: serif(size: 19, color: SadhanaColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _controls(),
                  ),
                  Expanded(
                    child: _verses.isEmpty
                        ? const Center(
                            child: Text('No verses in this chapter.'),
                          )
                        : PageView.builder(
                            controller: _pages,
                            itemCount: _verses.length,
                            onPageChanged: (index) => setState(() {
                              _index = index;
                              _syncVerse();
                            }),
                            itemBuilder: (context, i) => _VersePage(
                              verse: _verses[i],
                              show: _show,
                              translating: _translating == _verses[i].ref,
                              onTranslate: (language) =>
                                  _translate(_verses[i], language),
                            ),
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

  Widget _toolbar() => Row(
    children: [
      IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        color: SadhanaColors.ink,
        tooltip: 'Back',
      ),
      const Spacer(),
      IconButton(
        onPressed: _verses.isEmpty ? null : _toggleBookmark,
        tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark this verse',
        color: _bookmarked ? SadhanaColors.green : SadhanaColors.ink,
        icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border),
      ),
      IconButton(
        tooltip: 'Settings',
        color: SadhanaColors.gold,
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
        icon: const Icon(Icons.settings_outlined),
      ),
      const SizedBox(width: 4),
    ],
  );

  Widget _controls() => DecoratedBox(
    decoration: BoxDecoration(
      color: SadhanaColors.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x11000000),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (final mode in _Show.values)
            _ModeChip(
              key: ValueKey('show-${mode.name}'),
              label: switch (mode) {
                _Show.sanskrit => 'Sanskrit',
                _Show.meaning => 'Meaning',
                _Show.both => 'Both',
              },
              selected: _show == mode,
              onTap: () => setState(() => _show = mode),
            ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _index == 0 ? null : () => _goTo(_index - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            _verses.isEmpty ? '—' : '${_index + 1} of ${_verses.length}',
            style: const TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _index >= _verses.length - 1
                ? null
                : () => _goTo(_index + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? SadhanaColors.greenTint : Colors.transparent,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? SadhanaColors.green : SadhanaColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _VersePage extends StatelessWidget {
  const _VersePage({
    required this.verse,
    required this.show,
    required this.translating,
    required this.onTranslate,
  });

  final PassageView verse;
  final _Show show;
  final bool translating;
  final void Function(TargetLanguage language) onTranslate;

  @override
  Widget build(BuildContext context) {
    final translation = verse.translationFor(const ['en', 'hi']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DecoratedBox(
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Verse ${verse.label ?? verse.ref}',
                      style: serif(size: 17, color: SadhanaColors.ink),
                    ),
                    const Spacer(),
                    if (verse.meter case final meter?)
                      _Chip(text: 'Meter: $meter'),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 14),
                  width: 36,
                  height: 2,
                  color: SadhanaColors.gold,
                ),
                if (verse.speaker case final speaker?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      speaker,
                      style: serif(size: 16, color: SadhanaColors.green),
                    ),
                  ),
                if (show != _Show.meaning) ...[
                  Text(
                    verse.text,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.6,
                      color: SadhanaColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    verse.transliteration ?? devanagariToIast(verse.text),
                    style: serif(
                      size: 15,
                      style: FontStyle.italic,
                      color: SadhanaColors.inkSoft,
                      height: 1.45,
                    ),
                  ),
                ],
                if (show != _Show.sanskrit) ...[
                  if (show == _Show.both)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: SadhanaColors.line),
                    ),
                  _SectionLabel('Meaning'),
                  const SizedBox(height: 8),
                  if (translation == null)
                    const _Missing(
                      'No translation is installed for this verse yet.',
                    )
                  else ...[
                    Text(
                      translation.text,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.55,
                        color: SadhanaColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Credit(translation: translation),
                  ],
                  _TranslateOnPhone(
                    verse: verse,
                    translating: translating,
                    onTranslate: onTranslate,
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1, color: SadhanaColors.line),
                const SizedBox(height: 12),
                const _ListenChant(),
              ],
            ),
          ),
        ),
        if (verse.explanations.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel('Explanation'),
          const SizedBox(height: 8),
          for (final explanation in verse.explanations)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                explanation,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: SadhanaColors.ink,
                ),
              ),
            ),
        ],
        if (verse.takeaways.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionLabel('Key Takeaways'),
          const SizedBox(height: 6),
          for (final takeaway in verse.takeaways)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: 10),
                    child: CircleAvatar(
                      radius: 3,
                      backgroundColor: SadhanaColors.gold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      takeaway,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: SadhanaColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (verse.variants.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionLabel('Variant readings'),
          const SizedBox(height: 6),
          for (final variant in verse.variants)
            Text(
              variant,
              style: const TextStyle(
                fontSize: 15,
                color: SadhanaColors.inkSoft,
              ),
            ),
        ],
      ],
    );
  }
}

/// Offers a translation in any language the verse does not already have.
///
/// Nothing runs until the reader asks: the model is large and slow, and a
/// published translation is always the better one.
class _TranslateOnPhone extends StatelessWidget {
  const _TranslateOnPhone({
    required this.verse,
    required this.translating,
    required this.onTranslate,
  });

  final PassageView verse;
  final bool translating;
  final void Function(TargetLanguage language) onTranslate;

  @override
  Widget build(BuildContext context) {
    if (translating) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Translating on this phone…',
                style: TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
              ),
            ),
          ],
        ),
      );
    }

    final missing = [
      for (final language in TargetLanguage.all)
        if (!verse.hasTranslationIn(language.code)) language,
    ];
    if (missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Translate on this phone:',
            style: TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
          ),
          for (final language in missing)
            TextButton(
              key: ValueKey('translate-${language.code}'),
              onPressed: () => onTranslate(language),
              style: TextButton.styleFrom(
                foregroundColor: SadhanaColors.green,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(language.name),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: serif(size: 19, color: SadhanaColors.ink)),
      const SizedBox(height: 4),
      Container(width: 28, height: 2, color: SadhanaColors.gold),
    ],
  );
}

class _Credit extends StatelessWidget {
  const _Credit({required this.translation});

  final TranslationView translation;

  @override
  Widget build(BuildContext context) {
    final credit = [
      if (translation.machine) 'Machine translation',
      ?translation.translator,
    ].join('  ·  ');
    if (credit.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        if (translation.machine)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 15,
              color: SadhanaColors.inkSoft,
            ),
          ),
        Flexible(
          child: Text(
            credit,
            style: const TextStyle(fontSize: 12, color: SadhanaColors.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: const TextStyle(fontSize: 15, color: SadhanaColors.inkSoft),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF3EFE8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
      ),
    ),
  );
}

/// Chant audio arrives as a pack or is generated on the phone; until then the
/// control explains itself instead of doing nothing.
class _ListenChant extends StatelessWidget {
  const _ListenChant();

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(28),
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Chant audio isn't installed yet. It will arrive as a download.",
        ),
      ),
    ),
    child: const Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: SadhanaColors.green,
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Listen Chant',
              style: TextStyle(fontSize: 16, color: SadhanaColors.ink),
            ),
            Text(
              'Hear the verse in Sanskrit',
              style: TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
            ),
          ],
        ),
      ],
    ),
  );
}
