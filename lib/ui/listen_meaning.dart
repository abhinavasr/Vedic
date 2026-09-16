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
    text: '\${choice.text}\n\n\$explanation',
    locale: choice.locale,
    languageCode: choice.languageCode,
    description: '\${choice.description}, with the explanation',
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
  State<ListenMeaning> createState() => ListenMeaningState();
}

class ListenMeaningState extends State<ListenMeaning> {
  SpokenChoice? _choice;

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
    if (speaking) return speech.stop();
    final choice = _choice;
    if (choice == null) return;
    await widget.onBeforePlay?.call();
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
            ],
          ),
        );
      },
    );
  }
}
