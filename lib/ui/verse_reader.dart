import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/assistant.dart';
import '../ai/reading_languages.dart';
import '../ai/translation.dart';
import '../ai/verse_context.dart';
import '../core/transliteration.dart';
import '../library/scripture_repository.dart';
import '../packs/pack_store.dart';
import '../audio/listen_player.dart';
import 'ai/assistant_screen.dart';
import 'jump_sheet.dart';
import 'listen_meaning.dart';
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
    this.visiting = false,
  });

  final ScriptureRepository repository;
  final WorkSummary work;
  final SectionSummary section;

  /// The verse to open at, e.g. from the verse of the day.
  final String? initialRef;

  /// Whether this is a visit rather than a continuation.
  ///
  /// Arriving from the verse of the day drops someone into the middle of a
  /// book they may not be reading. Their place in it stays where they left it
  /// until they turn a page here, which is the point at which they are
  /// reading rather than looking.
  final bool visiting;

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

  /// The explanation being rendered into another language, if any.
  _Translating? _explaining;

  /// Whether the reader is being read to, verse after verse.
  var _continuous = false;

  /// The language last asked for, by verse. Someone who asks for Tamil means
  /// to read Tamil, whatever their usual language is.
  final _justTranslated = <String, String>{};

  /// The reading language, kept so the work running ahead can follow it
  /// across the awaits where there is no context to ask.
  ReadingLanguage? _reading;

  /// Work that came back unusable, so running ahead does not spend the next
  /// hour failing at the same verse.
  final _refused = <String>{};

  /// The run working ahead of the reader, while there is one.
  Future<void>? _ahead;

  /// The wait between page turn and background work, held so that leaving the
  /// reader ends it rather than leaving a timer running over a dead screen.
  Timer? _settle;
  Completer<void>? _settling;

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
    // The model is usually still loading when the reader opens. Start the
    // moment it can answer rather than waiting for the next page turn.
    Assistant.instance.state.addListener(_keepAhead);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reading = ReadingLanguageScope.of(context);
    if (identical(reading, _reading)) return _keepAhead();
    _reading = reading;
    // A language just chosen is a language to start filling in.
    _keepAhead();
  }

  /// How far ahead of the reader to work.
  ///
  /// Two pages: far enough that paging on finds the next verse already done,
  /// near enough that a reader who stops has not set the phone translating
  /// the rest of the chapter.
  static const _lookAhead = 2;

  /// Translates what the reader is about to reach, one piece at a time.
  ///
  /// Nothing here is asked for: a reader who has chosen a language means to
  /// read in it, and being shown the English while a button offers to fix it
  /// is a worse answer than simply having it ready. It runs only when the
  /// model is already installed and loaded — this never starts a download —
  /// and everything it produces is stored, so a verse is translated once on
  /// this phone and never again.
  void _keepAhead() {
    if (_ahead != null) return;
    _ahead = _runAhead().whenComplete(() => _ahead = null);
  }

  Future<void> _runAhead() async {
    // Let the page settle first: the reader is paging, and the first frames
    // matter more than the work behind them.
    await _pause(const Duration(milliseconds: 600));
    while (mounted) {
      final job = _nextAhead();
      if (job == null) return;
      final done = job.note
          ? await _explain(job.verse, job.language, automatic: true)
          : await _translate(job.verse, job.language, automatic: true);
      if (!done) _refused.add(_jobKey(job.verse.ref, job.language, job.note));
    }
  }

  /// Waits, and gives up waiting the moment the reader is gone.
  Future<void> _pause(Duration wait) {
    final waited = _settling = Completer<void>();
    _settle = Timer(wait, () {
      if (!waited.isCompleted) waited.complete();
    });
    return waited.future;
  }

  String _jobKey(String ref, TargetLanguage language, bool note) =>
      '$ref/${language.code}/${note ? 'note' : 'text'}';

  /// The next thing worth translating, nearest the reader first: each verse's
  /// meaning before its explanation, since that is what is read.
  ({PassageView verse, TargetLanguage language, bool note})? _nextAhead() {
    final language = _reading?.language;
    if (language == null) return null;
    if (!Assistant.instance.state.value.canAnswer) return null;
    for (var i = _index; i <= _index + _lookAhead && i < _verses.length; i++) {
      final verse = _verses[i];
      for (final note in const [false, true]) {
        if (_refused.contains(_jobKey(verse.ref, language, note))) continue;
        final has = note
            ? verse.noteLanguages(verse.explanations)
            : {for (final t in verse.translations) t.language};
        if (has.contains(language.code)) continue;
        // An explanation can only be rendered from one somebody wrote.
        if (note && _packNotes(verse).isEmpty) continue;
        return (verse: verse, language: language, note: note);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _continuous = false;
    _settle?.cancel();
    if (_settling?.isCompleted == false) _settling?.complete();
    Assistant.instance.state.removeListener(_keepAhead);
    VersePlayer.instance.stop();
    _pages.dispose();
    super.dispose();
  }

  /// Reads the verses aloud one after another, turning the page itself.
  ///
  /// Each verse waits for the voice to finish rather than for a guessed
  /// interval, so a long verse is never cut off and a short one never leaves
  /// a silence.
  Future<void> _readOn() async {
    final player = VersePlayer.instance;
    // Read once, before any awaiting: the language is a listenable and this
    // loop outlives several frames.
    final reading = ReadingLanguageScope.of(context);
    setState(() => _continuous = true);
    while (mounted && _continuous && _index < _verses.length) {
      final verse = _verses[_index];
      final segments = await listenSegments(verse, reading);
      if (!mounted || !_continuous) break;
      if (segments.isEmpty) {
        // Nothing to play here. Give the reader a moment to look at it.
        await Future<void>.delayed(const Duration(seconds: 3));
      } else {
        try {
          // False means it was stopped rather than finished, and a stop must
          // not turn the page.
          if (!await player.play(verse.ref, segments)) break;
        } on Object {
          break;
        }
      }
      if (!mounted || !_continuous) break;
      if (_index >= _verses.length - 1) break;
      _goTo(_index + 1);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (mounted) setState(() => _continuous = false);
  }

  /// A way to reach any verse in the work without leaving the reader.
  Future<void> _showJump() async {
    await _stopReading();
    if (!mounted) return;
    final target = await showJumpSheet(
      context,
      repository: widget.repository,
      work: widget.work,
      section: widget.section,
      currentRef: _verses.isEmpty ? null : _verses[_index].ref,
    );
    if (target == null || !mounted) return;
    if (target.section.id == widget.section.id) {
      final at = _verses.indexWhere((v) => v.ref == target.ref);
      if (at >= 0) _goTo(at);
      return;
    }
    // Another chapter: replace rather than stack, so Back still leaves the
    // reader rather than walking through every chapter visited.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VerseReaderScreen(
          repository: widget.repository,
          work: widget.work,
          section: target.section,
          initialRef: target.ref,
        ),
      ),
    );
  }

  Future<void> _stopReading() async {
    setState(() => _continuous = false);
    await VersePlayer.instance.stop();
  }

  PassageView? get _verse => _verses.isEmpty ? null : _verses[_index];

  /// Whether the reader has moved off the verse they arrived at.
  var _moved = false;

  /// Remembers where the reader is, and whether this verse is bookmarked.
  void _syncVerse() {
    final verse = _verse;
    if (verse == null) return;
    final pack = widget.work.pack.packId;
    if (!widget.visiting || _moved) {
      widget.repository.store.saveLastRead(
        packId: pack,
        workSlug: widget.work.slug,
        ref: verse.ref,
      );
    }
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

  /// Whether the model can answer, sending the reader to set it up if not.
  ///
  /// The download is large and never starts on its own, so asking for work the
  /// phone cannot do yet leads to the setup screen rather than an error — but
  /// only when the reader asked. Work running ahead of them gives up quietly
  /// instead: it was never requested, and a screen nobody asked for is worse
  /// than a verse that stays in the language the pack shipped.
  Future<bool> _assistantReady(
    Assistant assistant, {
    required bool automatic,
  }) async {
    if (assistant.state.value.phase == AssistantPhase.unknown) {
      await assistant.refresh();
    }
    if (!mounted) return false;
    if (assistant.state.value.canAnswer) return true;
    if (automatic) return false;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen()));
    return false;
  }

  /// The explanations the pack itself carries, by language, ready to render
  /// from. One of this phone's own would be a translation of a translation,
  /// twice removed from the person who wrote it.
  Map<String, String> _packNotes(PassageView verse) {
    final published = <String, String>{};
    for (final note in verse.explanations) {
      if (note.onThisPhone) continue;
      published[note.language] = [
        ?published[note.language],
        note.text,
      ].join('\n\n');
    }
    return published;
  }

  /// Renders this verse's explanation into another language, on this phone.
  ///
  /// It translates an explanation the pack carries; it never writes one. An
  /// explanation this app invented would be the model commenting on scripture
  /// from memory, which is exactly what it does not do.
  Future<bool> _explain(
    PassageView verse,
    TargetLanguage language, {
    bool automatic = false,
  }) async {
    final assistant = Assistant.instance;
    if (!await _assistantReady(assistant, automatic: automatic)) return false;

    final source = chooseNoteSource(
      target: language,
      available: _packNotes(verse),
    );
    if (source == null) return false;

    setState(
      () => _explaining = _Translating(
        ref: verse.ref,
        language: language,
        source: source,
      ),
    );
    try {
      var text = '';
      await for (final progress in translateNoteStream(
        assistant,
        note: source.text,
        from: source.languageName,
        language: language,
        about: [
          widget.work.title,
          if (widget.section.number case final number?) 'Chapter $number',
          'verse ${verse.label ?? verse.ref}',
        ].join(', '),
      )) {
        text = progress.text;
        if (!mounted) return false;
        setState(
          () => _explaining = _explaining?.with_(
            text: progress.text,
            thinking: progress.thinking,
          ),
        );
      }
      widget.repository.store.saveLocalNote(
        LocalTranslation(
          packId: widget.work.pack.packId,
          workSlug: widget.work.slug,
          ref: verse.ref,
          language: language.code,
          text: text,
          model: '${assistant.model.fileName} via ${source.languageCode}',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) return true;
      setState(
        () => _verses = widget.repository.verses(widget.work, widget.section),
      );
      return true;
    } on Exception catch (e) {
      if (!mounted) return false;
      // Work nobody asked for fails quietly; the verse simply stays in the
      // language it was already in.
      if (!automatic) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TranslationRejected
                  ? e.message
                  : 'The explanation did not finish. Try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _explaining = null);
    }
  }

  /// Translates a verse on this phone, once the reader has asked for it.
  ///
  /// With no model installed this leads to the setup screen instead: the
  /// download is large and never starts on its own.
  Future<bool> _translate(
    PassageView verse,
    TargetLanguage language, {
    bool automatic = false,
  }) async {
    // The pack's own rendering stands. Re-doing it here would replace a vetted
    // translation with a weaker one, and the reader did not ask for that —
    // they asked for a language they could not read the verse in. Guarded here
    // as well as in the buttons, so no path into this screen can start one.
    if (_fromPack(verse).contains(language.code)) return false;
    final assistant = Assistant.instance;
    if (!await _assistantReady(assistant, automatic: automatic)) return false;

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
        if (!mounted) return false;
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
      if (!mounted) return true;
      setState(() {
        // Only when they asked: a verse filled in ahead of the reader should
        // still follow their own language when they reach it.
        if (!automatic) _justTranslated[verse.ref] = language.code;
        _verses = widget.repository.verses(widget.work, widget.section);
      });
      return true;
    } on Exception catch (e) {
      if (!mounted) return false;
      if (!automatic) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TranslationRejected
                  ? e.message
                  : 'The translation did not finish. Try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _translating = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final chapter = section.number == null
        ? section.title ?? 'Other text'
        : '${divisionName(section)} ${section.number}'
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
                            onPageChanged: (index) {
                              setState(() {
                                _index = index;
                                _moved = true;
                                _syncVerse();
                              });
                              // Keep the work ahead of where they now are.
                              _keepAhead();
                            },
                            itemBuilder: (context, i) => _VersePage(
                              verse: _verses[i],
                              show: _show,
                              prefer: _justTranslated[_verses[i].ref],
                              translating: _translating?.ref == _verses[i].ref
                                  ? _translating
                                  : null,
                              onTranslate: (language) =>
                                  _translate(_verses[i], language),
                              explaining: _explaining?.ref == _verses[i].ref
                                  ? _explaining
                                  : null,
                              onExplain: (language) =>
                                  _explain(_verses[i], language),
                              onBeforePlay: _stopReading,
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

  // The row above the verse: what to show, read-on, and where you are.
  //
  // There used to be a chevron either side of the counter. They were the first
  // things to be pushed off the edge on a small screen or at a large font
  // size, and they were never needed: the verse is a PageView, so the gesture
  // that moves it is a swipe. Losing them gave the row back the width it was
  // overflowing by, and the three things left are the three that cannot be
  // done any other way.
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
          // The chips scroll rather than squeeze, so a font size that makes
          // "Sanskrit" wide enough to fill the row still leaves the counter
          // and the play button where they are.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('read-on'),
            visualDensity: VisualDensity.compact,
            tooltip: _continuous
                ? 'Stop reading'
                : 'Read on, verse after verse',
            color: SadhanaColors.green,
            onPressed: _verses.isEmpty
                ? null
                : () => _continuous ? _stopReading() : _readOn(),
            icon: Icon(
              _continuous
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill_rounded,
            ),
          ),
          InkWell(
            key: const ValueKey('jump'),
            borderRadius: BorderRadius.circular(12),
            onTap: _verses.isEmpty ? null : _showJump,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                _verses.isEmpty ? '—' : '${_index + 1} of ${_verses.length}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  color: SadhanaColors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
    required this.explaining,
    required this.onExplain,
    required this.onBeforePlay,
  });

  final PassageView verse;
  final _Show show;

  /// A language to show ahead of the reader's usual one, because they just
  /// asked for it on this verse.
  final String? prefer;

  /// Set while this verse is the one being translated.
  final _Translating? translating;
  final void Function(TargetLanguage language) onTranslate;

  /// Set while this verse's explanation is the one being rendered.
  final _Translating? explaining;
  final void Function(TargetLanguage language) onExplain;

  /// Lets reading-straight-through stand down when one verse is asked for.
  final Future<void> Function() onBeforePlay;

  @override
  Widget build(BuildContext context) {
    final reading = ReadingLanguageScope.of(context).language;
    final preference = ReadingLanguageScope.of(context).preference;
    // One language's notes, not every language's at once.
    final explanations = verse.notesFor(verse.explanations, preference);
    final explanationLanguage = verse.noteLanguageOf(
      verse.explanations,
      preference,
    );
    final takeaways = verse.notesFor(verse.takeaways, preference);
    final translation = verse.translationFor([
      ?prefer,
      ...ReadingLanguageScope.of(context).preference,
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
                // A Row with a Spacer put the meter hard against the right
                // edge, which is where it belongs until the words are wide
                // enough that there is no edge left — at a large font on a
                // narrow phone this overflowed by 500 pixels. Wrapping keeps
                // the same line when it fits and drops the chip underneath
                // when it does not.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Verse ${verse.label ?? verse.ref}',
                      style: serif(size: 17, color: SadhanaColors.ink),
                    ),
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
                ListenControl(verse: verse, onBeforePlay: onBeforePlay),
              ],
            ),
          ),
        ),
        if (explanations.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel('Explanation'),
          const SizedBox(height: 8),
          // Say which language this is when it is not the one asked for, for
          // the same reason the meaning does: a silent fallback looks like the
          // setting having done nothing.
          if (explanationLanguage != null &&
              explanationLanguage != reading.code) ...[
            _Missing(
              'No ${reading.name} explanation yet — showing '
              '${languageName(explanationLanguage)}.',
            ),
            const SizedBox(height: 8),
          ],
          for (final explanation in explanations)
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
          _ExplainOnPhone(
            verse: verse,
            explaining: explaining,
            onExplain: onExplain,
          ),
        ],
        if (takeaways.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionLabel('Key Takeaways'),
          const SizedBox(height: 6),
          for (final takeaway in takeaways)
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

    final fromPack = _fromPack(verse);
    // The reader's own language leads; English and Hindi follow because packs
    // usually carry them. Every other language is behind "More languages", so
    // the row stays a row rather than becoming a menu.
    final seen = <String>{};
    final missing = [
      for (final language in [
        ReadingLanguageScope.of(context).language,
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

/// Offers the explanation in a language the pack does not carry it in.
///
/// Only ever a rendering of an explanation somebody wrote — the model is never
/// asked to explain a verse itself. As with the meaning, whatever the pack
/// ships counts as covered, and only this phone's own work can be redone.
class _ExplainOnPhone extends StatelessWidget {
  const _ExplainOnPhone({
    required this.verse,
    required this.explaining,
    required this.onExplain,
  });

  final PassageView verse;
  final _Translating? explaining;
  final void Function(TargetLanguage language) onExplain;

  @override
  Widget build(BuildContext context) {
    if (explaining case final live?) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
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
                    'Putting the explanation into ${live.language.name}, '
                    'from the ${live.source.languageName}…',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
            if (live.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  live.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.55,
                    color: SadhanaColors.ink,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final fromPack = {
      for (final note in verse.explanations)
        if (!note.onThisPhone) note.language,
    };
    // Nothing shipped means nothing to render from: this is a translator, not
    // a commentator.
    if (fromPack.isEmpty) return const SizedBox.shrink();

    final reading = ReadingLanguageScope.of(context).language;
    final already = verse.noteLanguages(verse.explanations);
    // Only the reader's own language is offered here. Anything else would be
    // asking which language they want an explanation they cannot read in.
    if (fromPack.contains(reading.code)) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('explain-here'),
        onPressed: () => onExplain(reading),
        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
        label: Text(
          already.contains(reading.code)
              ? 'Explain again in ${reading.name}'
              : 'Explain in ${reading.name} on this phone',
        ),
        style: TextButton.styleFrom(
          foregroundColor: SadhanaColors.green,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

/// Whatever the pack carries counts as covered, machine-made or not: the
/// publisher shipped it, and re-translating it here would replace a vetted
/// rendering with a weaker one. Only what this phone made is redoable — that
/// one can be wrong, and the reader needs the button that made it rather than
/// a dead end.
Set<String> _fromPack(PassageView verse) => {
  for (final translation in verse.translations)
    if (!translation.onThisPhone) translation.language,
};

/// Every language the app can be asked for, with the ones the pack already
/// carries greyed out rather than merely ticked.
///
/// A tick beside a language still reads as a button, and it was: this sheet
/// was the one way left to start a translation the pack had already shipped.
Future<void> _pickLanguage(
  BuildContext context,
  PassageView verse,
  void Function(TargetLanguage language) onTranslate,
) async {
  final fromPack = _fromPack(verse);
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
              enabled: !fromPack.contains(language.code),
              title: Text(language.name),
              subtitle: fromPack.contains(language.code)
                  ? const Text('Already in this book')
                  : language.endonym == language.name
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
