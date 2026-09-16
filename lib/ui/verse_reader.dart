import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/assistant.dart';
import '../ai/reading_languages.dart';
import '../ai/translation.dart';
import '../ai/verse_context.dart';
import '../audio/speech.dart';
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

  /// The translation being written on this phone, if any.
  _Translating? _translating;

  /// The language last asked for, by verse. Someone who asks for Tamil means
  /// to read Tamil, whatever their usual language is.
  final _justTranslated = <String, String>{};

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

  VerseContext _contextFor(PassageView verse) {
    final index = _verses.indexWhere((v) => v.ref == verse.ref);
    return verseContext(
      workTitle: widget.work.title,
      section: widget.section,
      verse: verse,
      // At the top of a chapter the thread continues in the one before, so
      // the store is asked rather than this chapter's list.
      previous: index > 0
          ? _verses[index - 1]
          : widget.repository.verseBefore(widget.work, verse.ref),
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

    // Measured on a phone: going from a translation someone already made
    // beats going from the Sanskrit, in both directions
    // (docs/ON_DEVICE_AI.md). The pack's own renderings count; this phone's
    // do not.
    final source = chooseSource(
      target: language,
      original: verse.text,
      available: {
        for (final translation in verse.translations)
          if (!translation.onThisPhone) translation.language: translation.text,
      },
    );

    setState(
      () => _translating = _Translating(
        ref: verse.ref,
        language: language,
        source: source,
      ),
    );
    try {
      var text = '';
      await for (final progress in translateVerseStream(
        assistant,
        verse: source.text,
        from: source.languageName,
        language: language,
        context: source.isOriginal
            ? _contextFor(verse)
            // Translating a translation: the Sanskrit context would invite it
            // to answer from the original instead of the text it was given.
            : const VerseContext(),
      )) {
        text = progress.text;
        if (!mounted) return;
        // Only the final value has been checked, so what is shown while it
        // runs is never stored.
        setState(
          () => _translating = _translating?.with_(
            text: progress.text,
            thinking: progress.thinking,
          ),
        );
      }
      widget.repository.store.saveLocalTranslation(
        LocalTranslation(
          packId: widget.work.pack.packId,
          workSlug: widget.work.slug,
          ref: verse.ref,
          language: language.code,
          text: text,
          // The model and the text it worked from, which is what makes it
          // possible to re-translate everything a weaker one produced, or
          // everything that came the long way round through another language.
          model: source.isOriginal
              ? assistant.model.fileName
              : '${assistant.model.fileName} via ${source.languageCode}',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _justTranslated[verse.ref] = language.code;
        _verses = widget.repository.verses(widget.work, widget.section);
      });
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
                              prefer: _justTranslated[_verses[i].ref],
                              translating: _translating?.ref == _verses[i].ref
                                  ? _translating
                                  : null,
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

/// A translation being written on this phone, right now.
@immutable
class _Translating {
  const _Translating({
    required this.ref,
    required this.language,
    required this.source,
    this.text = '',
    this.thinking = '',
  });

  final String ref;
  final TargetLanguage language;

  /// What it is being translated out of, which the reader is told: a
  /// translation of a translation is a different claim.
  final TranslationSource source;

  /// What has arrived so far. Unchecked, so it is shown and not stored.
  final String text;

  /// The model's reasoning so far.
  final String thinking;

  _Translating with_({required String text, required String thinking}) =>
      _Translating(
        ref: ref,
        language: language,
        source: source,
        text: text,
        thinking: thinking,
      );
}

class _VersePage extends StatelessWidget {
  const _VersePage({
    required this.verse,
    required this.show,
    required this.prefer,
    required this.translating,
    required this.onTranslate,
  });

  final PassageView verse;
  final _Show show;

  /// A language to show ahead of the reader's usual one, because they just
  /// asked for it on this verse.
  final String? prefer;

  /// Set while this verse is the one being translated.
  final _Translating? translating;
  final void Function(TargetLanguage language) onTranslate;

  @override
  Widget build(BuildContext context) {
    final reading = ReadingLanguage.instance.language;
    final translation = verse.translationFor([
      ?prefer,
      ...ReadingLanguage.instance.preference,
    ]);
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
                    // Say which language this is when it is not the one the
                    // reader asked for. Falling back silently looks exactly
                    // like the setting having done nothing.
                    if (translation.language != reading.code &&
                        !verse.hasTranslationIn(reading.code)) ...[
                      _Missing(
                        'No ${reading.name} translation yet — showing '
                        '${languageName(translation.language)}.',
                      ),
                      const SizedBox(height: 8),
                    ],
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
                _ListenChant(verse: verse),
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

  /// Set while this verse is the one being translated.
  final _Translating? translating;
  final void Function(TargetLanguage language) onTranslate;

  @override
  Widget build(BuildContext context) {
    if (translating case final live?) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    live.text.isEmpty
                        ? 'Working it out in ${live.language.name}…'
                        : 'Translating from the '
                              '${live.source.languageName} '
                              'into ${live.language.name}…',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
            // The reasoning, while there is nothing better to show. Honest,
            // and better than watching it think in silence.
            if (live.text.isEmpty && live.thinking.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  live.thinking,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: serif(
                    size: 13,
                    style: FontStyle.italic,
                    color: SadhanaColors.inkSoft,
                    height: 1.4,
                  ),
                ),
              ),
            if (live.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  live.text,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.55,
                    color: SadhanaColors.ink,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Whatever the pack carries counts as covered, machine-made or not: the
    // publisher shipped it, and re-translating it here would replace a vetted
    // rendering with a weaker one. Only what this phone made is redoable —
    // that one can be wrong, and the reader needs the button that made it
    // rather than a dead end.
    final fromPack = {
      for (final translation in verse.translations)
        if (!translation.onThisPhone) translation.language,
    };
    // The reader's own language leads; English and Hindi follow because packs
    // usually carry them. Every other language is behind "More languages", so
    // the row stays a row rather than becoming a menu.
    final seen = <String>{};
    final missing = [
      for (final language in [
        ReadingLanguage.instance.language,
        TargetLanguage.english,
        TargetLanguage.hindi,
      ])
        if (!fromPack.contains(language.code) && seen.add(language.code))
          language,
    ];
    final again = missing.any(
      (language) => verse.hasTranslationIn(language.code),
    );
    // Nothing to offer up front, but every other language is still a tap
    // away — without a label promising work that is already done.
    if (missing.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('translate-more'),
          onPressed: () => _pickLanguage(context, verse, onTranslate),
          style: TextButton.styleFrom(
            foregroundColor: SadhanaColors.inkSoft,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Translate into another language…'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            again
                ? 'Translate again on this phone:'
                : 'Translate on this phone:',
            style: const TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
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
          TextButton(
            key: const ValueKey('translate-more'),
            onPressed: () => _pickLanguage(context, verse, onTranslate),
            style: TextButton.styleFrom(
              foregroundColor: SadhanaColors.inkSoft,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('More languages…'),
          ),
        ],
      ),
    );
  }
}

/// Every language the app can be asked for, with what the verse already has
/// marked so the reader is not offered work that is already done.
Future<void> _pickLanguage(
  BuildContext context,
  PassageView verse,
  void Function(TargetLanguage language) onTranslate,
) async {
  final chosen = await showModalBottomSheet<TargetLanguage>(
    context: context,
    backgroundColor: SadhanaColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Translate this verse into',
              style: serif(size: 20, color: SadhanaColors.ink),
            ),
          ),
          for (final language in TargetLanguage.all)
            ListTile(
              key: ValueKey('sheet-${language.code}'),
              title: Text(language.name),
              subtitle: language.endonym == language.name
                  ? null
                  : Text(language.endonym),
              trailing: verse.hasTranslationIn(language.code)
                  ? const Icon(
                      Icons.check,
                      size: 18,
                      color: SadhanaColors.green,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(language),
            ),
        ],
      ),
    ),
  );
  if (chosen != null) onTranslate(chosen);
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
      languageName(translation.language),
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

/// Sounds the verse out.
///
/// No pack carries a recorded chant yet, so this is the phone's own voice
/// reading the phonetic. That is a different thing from a chant and the
/// control says so; when a pack brings a recording, the recording takes this
/// place.
class _ListenChant extends StatefulWidget {
  const _ListenChant({required this.verse});

  final PassageView verse;

  @override
  State<_ListenChant> createState() => _ListenChantState();
}

class _ListenChantState extends State<_ListenChant> {
  SpokenChoice? _choice;

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void didUpdateWidget(_ListenChant old) {
    super.didUpdateWidget(old);
    if (old.verse.ref != widget.verse.ref) _pick();
  }

  /// Which language this phone can read this verse in. Asked once per verse,
  /// because listing the installed voices touches the platform.
  Future<void> _pick() async {
    final choice = await VerseSpeech.instance.chooseForChant(
      verse: widget.verse.text,
      transliteration: widget.verse.transliteration,
    );
    if (mounted) setState(() => _choice = choice);
  }

  Future<void> _tap(bool speaking) async {
    final speech = VerseSpeech.instance;
    if (speaking) return speech.stop();
    final choice = _choice;
    if (choice == null) return;
    try {
      await speech.speak(widget.verse.ref, choice);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This phone could not read it aloud.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: VerseSpeech.instance.speaking,
    builder: (context, ref, _) {
      final speaking = ref == widget.verse.ref;
      final choice = _choice;
      return InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: choice == null
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This phone has no voice for the languages this verse is '
                    'in, and no chant is installed.',
                  ),
                ),
              )
            : () => _tap(speaking),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: choice == null
                  ? SadhanaColors.inkSoft
                  : SadhanaColors.green,
              child: Icon(
                speaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    speaking ? 'Stop' : 'Listen Chant',
                    style: const TextStyle(
                      fontSize: 16,
                      color: SadhanaColors.ink,
                    ),
                  ),
                  Text(
                    choice?.description ??
                        'This phone has no voice that can read it',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
