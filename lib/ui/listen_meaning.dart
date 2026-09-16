import 'dart:io';

import 'package:flutter/material.dart';

import '../ai/reading_languages.dart';
import '../audio/listen_player.dart';
import '../audio/speech.dart';
import '../library/scripture_repository.dart';
import 'theme.dart';

/// Where a verse's chant comes from, once one has been published for it.
///
/// A hook rather than a dependency: the reader asks for a recording and gets
/// one or gets nothing, and everything above here works the same either way.
/// Packs without audio, and builds without a vault key, simply answer null.
class ChantSource {
  ChantSource({Future<File?> Function(PassageView verse)? find})
    : _find = find ?? ((_) async => null);

  /// The app's. Replaceable in tests, and wired up at startup.
  static ChantSource instance = ChantSource();

  final Future<File?> Function(PassageView verse) _find;

  Future<File?> find(PassageView verse) => _find(verse);
}

/// What playing this verse will play, in order: the chant as recorded, then
/// the meaning, then the explanation — whichever of them the reader asked for.
///
/// Returns an empty list when there is nothing to play, which is not an error:
/// a verse with no recording, no translation and no explanation is simply a
/// verse the app cannot read aloud yet.
Future<List<ListenSegment>> listenSegments(
  PassageView verse,
  ReadingLanguage reading,
) async {
  final mix = reading.mix;
  final segments = <ListenSegment>[];

  if (mix.chant) {
    final file = await ChantSource.instance.find(verse);
    if (file != null) segments.add(ChantSegment(file));
  }
  if (!mix.meaning && !mix.explanation) return segments;

  final choice = await VerseSpeech.instance.chooseForMeaning(
    available: {
      for (final translation in verse.translations)
        translation.language: translation.text,
    },
    preferred: reading.language.code,
  );
  if (choice == null) return segments;
  if (mix.meaning) segments.add(SpokenSegment(choice));
  if (mix.explanation) {
    // Read in the same language as the meaning, so one voice is never asked
    // to read two languages in a row.
    final explanation = verse
        .notesFor(verse.explanations, [choice.languageCode])
        .join(' ');
    if (explanation.isNotEmpty) {
      segments.add(
        SpokenSegment(
          SpokenChoice(
            text: explanation,
            locale: choice.locale,
            languageCode: choice.languageCode,
            description: choice.description,
          ),
        ),
      );
    }
  }
  return segments;
}

/// The play control, and beside it the three things it can play.
///
/// The choice lives here rather than in Settings because it is not a
/// preference so much as a mood: the chant alone this morning, the meaning and
/// the explanation on tonight's walk. It is remembered, so it only has to be
/// said once, but it is always one tap from the verse it applies to.
class ListenControl extends StatefulWidget {
  const ListenControl({
    super.key,
    required this.verse,
    this.onBeforePlay,
    this.compact = false,
  });

  final PassageView verse;

  /// Called before this verse plays, so a reader that is reading straight
  /// through can stand down rather than compete for the speaker.
  final Future<void> Function()? onBeforePlay;

  /// Drops the chips, for a card with no room for them and no explanation on
  /// it to switch on.
  final bool compact;

  @override
  State<ListenControl> createState() => _ListenControlState();
}

class _ListenControlState extends State<ListenControl> {
  /// What is available for this verse: the chips offer nothing that is not.
  var _hasChant = false;
  String? _spokenLanguage;

  /// What the offer was worked out for, so a language or a mix chosen
  /// elsewhere is picked up rather than leaving a stale line.
  ({String language, String mix})? _madeFor;
  var _asked = 0;

  bool get _hasExplanation => widget.verse.explanations.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reading = ReadingLanguageScope.of(context);
    final now = (language: reading.language.code, mix: reading.mix.code);
    if (_madeFor == now) return;
    _madeFor = now;
    _look(reading);
  }

  @override
  void didUpdateWidget(ListenControl old) {
    super.didUpdateWidget(old);
    if (old.verse.ref != widget.verse.ref) {
      _look(ReadingLanguageScope.of(context));
    }
  }

  /// What this verse can offer. Asked once per verse, because finding a
  /// recording and listing the installed voices both touch the platform.
  Future<void> _look(ReadingLanguage reading) async {
    final asked = ++_asked;
    final chant = await ChantSource.instance.find(widget.verse);
    final choice = await VerseSpeech.instance.chooseForMeaning(
      available: {
        for (final translation in widget.verse.translations)
          translation.language: translation.text,
      },
      preferred: reading.language.code,
    );
    if (!mounted || asked != _asked) return;
    setState(() {
      _hasChant = chant != null;
      _spokenLanguage = choice == null ? null : languageOf(choice);
    });
  }

  Future<void> _tap(bool playing, ReadingLanguage reading) async {
    final player = VersePlayer.instance;
    // Either way this verse is taking the speaker, so reading-straight-through
    // stands down first — otherwise stopping here looks like a page turn.
    await widget.onBeforePlay?.call();
    if (playing) return player.stop();
    final segments = await listenSegments(widget.verse, reading);
    if (!mounted) return;
    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to play for this verse yet.')),
      );
      return;
    }
    try {
      await player.play(widget.verse.ref, segments);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This phone could not play it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = ReadingLanguageScope.of(context);
    final mix = reading.mix;
    // Nothing this verse can offer, so no control at all rather than a button
    // that does nothing.
    if (!_hasChant && _spokenLanguage == null) return const SizedBox.shrink();

    return ValueListenableBuilder<String?>(
      valueListenable: VersePlayer.instance.playing,
      builder: (context, ref, _) {
        final playing = ref == widget.verse.ref;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: mix.isSilent ? null : () => _tap(playing, reading),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: mix.isSilent
                        ? SadhanaColors.inkSoft
                        : SadhanaColors.green,
                    child: Icon(
                      playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
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
                          playing ? 'Stop' : 'Listen',
                          style: const TextStyle(
                            fontSize: 16,
                            color: SadhanaColors.ink,
                          ),
                        ),
                        Text(
                          mix.describe(language: _spokenLanguage),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
            ),
            if (!widget.compact) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_hasChant)
                    _MixChip(
                      label: 'Chant',
                      icon: Icons.graphic_eq,
                      on: mix.chant,
                      onChanged: (on) =>
                          reading.mix = mix.with_(chant: on),
                    ),
                  if (_spokenLanguage != null)
                    _MixChip(
                      label: 'Meaning',
                      icon: Icons.translate,
                      on: mix.meaning,
                      onChanged: (on) =>
                          reading.mix = mix.with_(meaning: on),
                    ),
                  if (_hasExplanation && _spokenLanguage != null)
                    _MixChip(
                      label: 'Explanation',
                      icon: Icons.notes,
                      on: mix.explanation,
                      onChanged: (on) =>
                          reading.mix = mix.with_(explanation: on),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// What the meaning will be read in, which is not always what was asked for.
String languageOf(SpokenChoice choice) =>
    choice.description.replaceFirst('Read aloud in ', '');

/// One of the three things a verse can be listened to as.
class _MixChip extends StatelessWidget {
  const _MixChip({
    required this.label,
    required this.icon,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool on;
  final void Function(bool on) onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: on ? SadhanaColors.greenTint : Colors.transparent,
    shape: StadiumBorder(
      side: BorderSide(
        color: on ? SadhanaColors.green : SadhanaColors.line,
      ),
    ),
    child: InkWell(
      key: ValueKey('mix-${label.toLowerCase()}'),
      customBorder: const StadiumBorder(),
      onTap: () => onChanged(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check : icon,
              size: 15,
              color: on ? SadhanaColors.green : SadhanaColors.inkSoft,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: on ? SadhanaColors.green : SadhanaColors.inkSoft,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
