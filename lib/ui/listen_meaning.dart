import 'package:flutter/material.dart';

import '../ai/reading_languages.dart';
import '../audio/speech.dart';
import '../library/scripture_repository.dart';
import 'theme.dart';

/// What to read aloud for a verse: its meaning, and its explanation too when
/// the reader has asked for that.
Future<SpokenChoice?> spokenVerse(
  PassageView verse,
  ReadingLanguage reading,
) async {
  final choice = await VerseSpeech.instance.chooseForMeaning(
    available: {
      for (final translation in verse.translations)
        translation.language: translation.text,
    },
    preferred: reading.language.code,
  );
  if (choice == null || !reading.withExplanation) return choice;
  // The explanation is only read in the same language as the meaning, so one
  // voice is not asked to read two languages in a row.
  final explanation = verse
      .notesFor(verse.explanations, [choice.languageCode])
      .join(' ');
  if (explanation.isEmpty) return choice;
  return SpokenChoice(
    text: '${choice.text}\n\n$explanation',
    locale: choice.locale,
    languageCode: choice.languageCode,
    description: '${choice.description}, with the explanation',
  );
}

/// Reads the verse's meaning aloud.
///
/// There is no chant here. A chant has to be a recording by someone who knows
/// the text, and no pack carries one yet; a phone sounding the Sanskrit out
/// from its transliteration was tried and was not worth offering. The meaning
/// is a different matter, and a phone reads it perfectly well.
class ListenMeaning extends StatefulWidget {
  const ListenMeaning({super.key, required this.verse, this.onBeforePlay});

  final PassageView verse;

  /// Called before this verse is read, so a reader that is reading straight
  /// through can stand down rather than compete for the voice.
  final Future<void> Function()? onBeforePlay;

  @override
  State<ListenMeaning> createState() => _ListenMeaningState();
}

class _ListenMeaningState extends State<ListenMeaning> {
  SpokenChoice? _choice;

  /// Whether this verse has an explanation to add at all.
  bool get _hasExplanation => widget.verse.explanations.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void didUpdateWidget(ListenMeaning oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verse.ref != widget.verse.ref) _pick();
  }

  /// Which language this phone can read this verse in. Asked once per verse,
  /// because listing the installed voices touches the platform.
  Future<void> _pick() async {
    final reading = ReadingLanguageScope.of(context);
    final choice = await spokenVerse(widget.verse, reading);
    if (mounted) setState(() => _choice = choice);
  }

  Future<void> _tap(bool speaking) async {
    final speech = VerseSpeech.instance;
    // Either way this verse is taking the voice, so reading-straight-through
    // stands down first — otherwise stopping here looks like a page turn.
    await widget.onBeforePlay?.call();
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
  Widget build(BuildContext context) {
    final choice = _choice;
    if (choice == null) return const SizedBox.shrink();
    return ValueListenableBuilder<String?>(
      valueListenable: VerseSpeech.instance.speaking,
      builder: (context, ref, _) {
        final speaking = ref == widget.verse.ref;
        final reading = ReadingLanguageScope.of(context);
        return InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _tap(speaking),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: SadhanaColors.green,
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
                      speaking ? 'Stop' : 'Listen to the meaning',
                      style: const TextStyle(
                        fontSize: 16,
                        color: SadhanaColors.ink,
                      ),
                    ),
                    Text(
                      '${choice.description}, this verse only',
                      style: const TextStyle(
                        fontSize: 13,
                        color: SadhanaColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              // The choice belongs beside the control it changes, not in a
              // settings screen two taps away. It is remembered either way.
              if (_hasExplanation)
                _WithExplanation(
                  on: reading.withExplanation,
                  onChanged: (on) {
                    reading.withExplanation = on;
                    _pick();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A small switch beside the listen control: read the explanation too.
class _WithExplanation extends StatelessWidget {
  const _WithExplanation({required this.on, required this.onChanged});

  final bool on;
  final void Function(bool on) onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: on
        ? 'The explanation is read too'
        : 'Read the explanation as well',
    child: Material(
      color: on ? SadhanaColors.greenTint : Colors.transparent,
      shape: const StadiumBorder(side: BorderSide(color: SadhanaColors.line)),
      child: InkWell(
        key: const ValueKey('with-explanation'),
        customBorder: const StadiumBorder(),
        onTap: () => onChanged(!on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check : Icons.add,
                size: 15,
                color: on ? SadhanaColors.green : SadhanaColors.inkSoft,
              ),
              const SizedBox(width: 4),
              Text(
                'Explanation',
                style: TextStyle(
                  fontSize: 12,
                  color: on ? SadhanaColors.green : SadhanaColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
