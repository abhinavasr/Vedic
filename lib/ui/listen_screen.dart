import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/fill_ahead.dart';
import '../ai/reading_languages.dart';
import '../ai/translation.dart';
import '../audio/listen_player.dart';
import '../library/scripture_repository.dart';
import 'listen_meaning.dart';
import 'theme.dart';

/// Listening, rather than reading.
///
/// One verse at a time, played straight through, with the three clips a
/// listener can choose between and a language for each of the two that have
/// one. The chant has no language: it is a recording of the Sanskrit.
///
/// The reader can play a verse too, but this is a different thing — nothing to
/// read, nothing to scroll, and it keeps going on its own.
class ListenScreen extends StatefulWidget {
  const ListenScreen({
    super.key,
    required this.repository,
    required this.work,
    required this.section,
    this.startAt,
  });

  final ScriptureRepository repository;
  final WorkSummary work;
  final SectionSummary section;
  final String? startAt;

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  late SectionSummary _section = widget.section;
  late var _verses = widget.repository.verses(widget.work, _section);
  late var _index = _startingIndex();
  late final FillAhead _fill = FillAhead(
    repository: widget.repository,
    work: widget.work,
  );

  /// Whether the listener has asked for it to keep going.
  var _playing = false;
  ReadingLanguage? _reading;

  int _startingIndex() {
    final at = widget.startAt;
    if (at == null) return 0;
    final found = _verses.indexWhere((v) => v.ref == at);
    return found < 0 ? 0 : found;
  }

  @override
  void initState() {
    super.initState();
    // Re-read the passages whenever the phone has written another translation,
    // so a verse filled in while this one plays is ready when it is reached.
    _fill.onFilled = () {
      if (!mounted) return;
      setState(() => _verses = widget.repository.verses(widget.work, _section));
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reading = ReadingLanguageScope.of(context);
    _fillAhead();
  }

  @override
  void dispose() {
    _playing = false;
    VersePlayer.instance.stop();
    super.dispose();
  }

  PassageView? get _verse =>
      _index >= 0 && _index < _verses.length ? _verses[_index] : null;

  /// The verses about to be heard, for the phone to translate before they are.
  void _fillAhead() {
    final reading = _reading;
    if (reading == null) return;
    _fill.keep(
      upcoming: () => [
        for (var i = _index; i <= _index + lookAhead && i < _verses.length; i++)
          _verses[i],
      ],
      // The meaning's language, since that is what is played. Read fresh each
      // time, so changing it mid-session changes what is worked on next.
      language: () =>
          TargetLanguage.forCode(reading.mix.meaningIn(reading.language.code)) ??
          reading.language,
      notes: reading.mix.explanation,
    );
  }

  /// Plays from here, verse after verse, until it is stopped or runs out.
  Future<void> _playOn() async {
    final reading = _reading;
    if (reading == null) return;
    setState(() => _playing = true);
    while (mounted && _playing) {
      final verse = _verse;
      if (verse == null) break;
      _fillAhead();
      final segments = await listenSegments(verse, reading);
      if (!mounted || !_playing) break;
      if (segments.isEmpty) {
        // Nothing for this verse yet. Wait rather than racing to the end of
        // the chapter in silence.
        await Future<void>.delayed(const Duration(seconds: 2));
      } else {
        try {
          // False means stopped rather than finished, and a stop must not
          // advance.
          if (!await VersePlayer.instance.play(verse.ref, segments)) break;
        } on Object {
          break;
        }
      }
      if (!mounted || !_playing) break;
      if (_index >= _verses.length - 1) break;
      setState(() => _index++);
    }
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _stop() async {
    setState(() => _playing = false);
    await VersePlayer.instance.stop();
  }

  /// Moves, and keeps playing if it was playing.
  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _verses.length) return;
    final wasPlaying = _playing;
    await _stop();
    if (!mounted) return;
    setState(() => _index = index);
    _fillAhead();
    if (wasPlaying) unawaited(_playOn());
  }

  Future<void> _goToSection(SectionSummary section) async {
    final wasPlaying = _playing;
    await _stop();
    if (!mounted) return;
    setState(() {
      _section = section;
      _verses = widget.repository.verses(widget.work, section);
      _index = 0;
    });
    _fillAhead();
    if (wasPlaying) unawaited(_playOn());
  }

  @override
  Widget build(BuildContext context) {
    final reading = ReadingLanguageScope.of(context);
    final mix = reading.mix;
    final verse = _verse;

    return Scaffold(
      backgroundColor: SadhanaColors.background,
      appBar: AppBar(
        backgroundColor: SadhanaColors.background,
        foregroundColor: SadhanaColors.ink,
        elevation: 0,
        title: Text('Listen', style: serif(size: 22, color: SadhanaColors.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            _ChapterStrip(
              sections: widget.repository.sections(widget.work),
              chosen: _section,
              onChosen: _goToSection,
            ),
            const SizedBox(height: 20),
            _NowPlaying(
              work: widget.work,
              verse: verse,
              position: _index + 1,
              of: _verses.length,
            ),
            const SizedBox(height: 20),
            _Transport(
              playing: _playing,
              canGoBack: _index > 0,
              canGoOn: _index < _verses.length - 1,
              onBack: () => _goTo(_index - 1),
              onOn: () => _goTo(_index + 1),
              onPlay: mix.isSilent ? null : () => _playing ? _stop() : _playOn(),
            ),
            const SizedBox(height: 28),
            Text(
              'What to play',
              style: serif(size: 18, color: SadhanaColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              mix.describe(reading: reading.language.code, nameOf: languageName),
              style: const TextStyle(
                fontSize: 13,
                color: SadhanaColors.inkSoft,
              ),
            ),
            const SizedBox(height: 12),
            _ClipRow(
              label: 'Chant',
              // Sanskrit, and nothing to choose: it is a recording.
              detail: 'Sanskrit',
              on: mix.chant,
              onChanged: (on) => reading.mix = mix.with_(chant: on),
            ),
            _ClipRow(
              label: 'Meaning',
              detail: languageName(mix.meaningIn(reading.language.code)),
              on: mix.meaning,
              onChanged: (on) => reading.mix = mix.with_(meaning: on),
              onLanguage: () => _pickLanguage(
                title: 'Read the meaning in',
                chosen: mix.meaningIn(reading.language.code),
                onChosen: (code) => reading.mix = code == null
                    ? mix.with_(clearMeaningLanguage: true)
                    : mix.with_(meaningLanguage: code),
              ),
            ),
            _ClipRow(
              label: 'Explanation',
              detail: languageName(mix.explanationIn(reading.language.code)),
              on: mix.explanation,
              onChanged: (on) => reading.mix = mix.with_(explanation: on),
              onLanguage: () => _pickLanguage(
                title: 'Read the explanation in',
                chosen: mix.explanationIn(reading.language.code),
                onChosen: (code) => reading.mix = code == null
                    ? mix.with_(clearExplanationLanguage: true)
                    : mix.with_(explanationLanguage: code),
              ),
            ),
            if (_fill.busy) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Translating the verses coming up, on this phone…',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickLanguage({
    required String title,
    required String chosen,
    required void Function(String? code) onChosen,
  }) async {
    final picked = await showModalBottomSheet<String>(
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
                title,
                style: serif(size: 20, color: SadhanaColors.ink),
              ),
            ),
            ListTile(
              key: const ValueKey('clip-language-follow'),
              title: const Text('Follow my reading language'),
              onTap: () => Navigator.of(context).pop('follow'),
            ),
            const Divider(height: 1),
            for (final language in TargetLanguage.all)
              ListTile(
                key: ValueKey('clip-language-${language.code}'),
                title: Text(language.name),
                subtitle: language.endonym == language.name
                    ? null
                    : Text(language.endonym),
                trailing: language.code == chosen
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: SadhanaColors.green,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(language.code),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    onChosen(picked == 'follow' ? null : picked);
    _fillAhead();
  }
}

/// Which chapter is being listened to.
class _ChapterStrip extends StatelessWidget {
  const _ChapterStrip({
    required this.sections,
    required this.chosen,
    required this.onChosen,
  });

  final List<SectionSummary> sections;
  final SectionSummary chosen;
  final void Function(SectionSummary section) onChosen;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('listen-chapter-${section.number}'),
              label: Text(section.number ?? section.title ?? 'Other'),
              selected: section.id == chosen.id,
              onSelected: (_) => onChosen(section),
            ),
          ),
      ],
    ),
  );
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.work,
    required this.verse,
    required this.position,
    required this.of,
  });

  final WorkSummary work;
  final PassageView? verse;
  final int position;
  final int of;

  @override
  Widget build(BuildContext context) {
    final verse = this.verse;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verse == null
                ? work.title
                : '${work.title}  ·  ${verse.label ?? verse.ref}',
            style: const TextStyle(
              fontSize: 13,
              color: SadhanaColors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            verse?.text ?? 'Nothing to play here.',
            style: const TextStyle(
              fontSize: 20,
              height: 1.6,
              color: SadhanaColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '$position of $of',
            style: const TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// Back, play, on. The listener is not reading, so these are the whole of the
/// navigation and they are the size of a thumb.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    required this.canGoBack,
    required this.canGoOn,
    required this.onBack,
    required this.onOn,
    required this.onPlay,
  });

  final bool playing;
  final bool canGoBack;
  final bool canGoOn;
  final VoidCallback onBack;
  final VoidCallback onOn;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        key: const ValueKey('listen-back'),
        iconSize: 34,
        color: SadhanaColors.ink,
        onPressed: canGoBack ? onBack : null,
        icon: const Icon(Icons.skip_previous_rounded),
        tooltip: 'The verse before',
      ),
      const SizedBox(width: 16),
      Material(
        color: onPlay == null ? SadhanaColors.inkSoft : SadhanaColors.green,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('listen-play'),
          customBorder: const CircleBorder(),
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      IconButton(
        key: const ValueKey('listen-on'),
        iconSize: 34,
        color: SadhanaColors.ink,
        onPressed: canGoOn ? onOn : null,
        icon: const Icon(Icons.skip_next_rounded),
        tooltip: 'The next verse',
      ),
    ],
  );
}

/// One of the three clips: whether it plays, and what language it plays in.
class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.label,
    required this.detail,
    required this.on,
    required this.onChanged,
    this.onLanguage,
  });

  final String label;
  final String detail;
  final bool on;
  final void Function(bool on) onChanged;

  /// Absent for the chant, which is in Sanskrit and always will be.
  final VoidCallback? onLanguage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: on ? SadhanaColors.greenTint : SadhanaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('clip-${label.toLowerCase()}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: on ? SadhanaColors.green : SadhanaColors.inkSoft,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: SadhanaColors.ink,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (onLanguage == null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
                )
              else
                TextButton(
                  key: ValueKey('clip-language-of-${label.toLowerCase()}'),
                  onPressed: onLanguage,
                  style: TextButton.styleFrom(
                    foregroundColor: SadhanaColors.green,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(detail, style: const TextStyle(fontSize: 13)),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
