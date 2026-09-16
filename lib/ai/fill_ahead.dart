import 'dart:async';

import '../library/scripture_repository.dart';
import '../packs/pack_store.dart';
import 'assistant.dart';
import 'translation.dart';
import 'verse_context.dart';

// Filling in a language the pack does not carry, just ahead of whoever is
// using it.
//
// A reader who picks a language means to read in it, and a listener who picks
// one means to hear it. Being shown the English with a button offering to fix
// it is a worse answer than simply having it ready — so the next couple of
// passages are translated before they are reached, and everything produced is
// stored, so a verse is translated once on this phone and never again.
//
// It lives here rather than in the reader because the listener needs exactly
// the same thing, two verses ahead of the speaker instead of two pages ahead
// of the eye.

/// How far ahead to work.
///
/// Two: far enough that moving on finds the next one done, near enough that
/// someone who stops has not set their phone translating the rest of the book.
const lookAhead = 2;

/// One piece of missing work.
class _Job {
  const _Job(this.verse, this.language, {required this.note});

  final PassageView verse;
  final TargetLanguage language;

  /// The explanation rather than the meaning.
  final bool note;

  String get key => '${verse.ref}/${language.code}/${note ? 'note' : 'text'}';
}

/// Translates what is coming up, one piece at a time.
class FillAhead {
  FillAhead({
    required this.repository,
    required this.work,
    Assistant? assistant,
  }) : assistant = assistant ?? Assistant.instance;

  final ScriptureRepository repository;
  final WorkSummary work;
  final Assistant assistant;

  /// Work that came back unusable, so this does not spend the next hour
  /// failing at the same verse.
  final _refused = <String>{};

  Future<void>? _running;

  /// Called when something has been written, so the caller can re-read the
  /// passages it is showing.
  void Function()? onFilled;

  /// Whether anything is being translated right now.
  bool get busy => _running != null;

  /// Keeps [upcoming] filled in, in [language].
  ///
  /// Safe to call as often as the position changes: one run at a time, and a
  /// run already going re-reads the list rather than starting a second.
  void keep({
    required List<PassageView> Function() upcoming,
    required TargetLanguage Function() language,
    bool notes = true,
  }) {
    if (_running != null) return;
    _running = _run(upcoming, language, notes).whenComplete(() {
      _running = null;
    });
  }

  Future<void> _run(
    List<PassageView> Function() upcoming,
    TargetLanguage Function() language,
    bool notes,
  ) async {
    while (true) {
      final job = _next(upcoming(), language(), notes);
      if (job == null) return;
      final done = job.note ? await _fillNote(job) : await _fillText(job);
      if (!done) _refused.add(job.key);
      onFilled?.call();
    }
  }

  /// The next thing worth translating, nearest first: each verse's meaning
  /// before its explanation, since that is what is heard first.
  _Job? _next(
    List<PassageView> upcoming,
    TargetLanguage language,
    bool notes,
  ) {
    // Never starts a download, and never wakes a model that is not loaded.
    if (!assistant.state.value.canAnswer) return null;
    for (final verse in upcoming) {
      for (final note in notes ? const [false, true] : const [false]) {
        final job = _Job(verse, language, note: note);
        if (_refused.contains(job.key)) continue;
        final has = note
            ? verse.noteLanguages(verse.explanations)
            : {for (final t in verse.translations) t.language};
        if (has.contains(language.code)) continue;
        // An explanation can only be rendered from one somebody wrote.
        if (note && packNotes(verse).isEmpty) continue;
        return job;
      }
    }
    return null;
  }

  /// Translates one verse. Returns whether anything was stored.
  Future<bool> _fillText(_Job job) async {
    // Measured on a phone: going from a translation someone already made beats
    // going from the Sanskrit, in both directions (docs/ON_DEVICE_AI.md). The
    // pack's own renderings count; this phone's do not.
    final source = chooseSource(
      target: job.language,
      original: job.verse.text,
      available: {
        for (final t in job.verse.translations)
          if (!t.onThisPhone) t.language: t.text,
      },
    );
    try {
      final text = await translateVerse(
        assistant,
        verse: source.text,
        from: source.languageName,
        language: job.language,
        context: source.isOriginal
            ? verseContext(
                workTitle: work.title,
                section: null,
                verse: job.verse,
                previous: repository.verseBefore(work, job.verse.ref),
              )
            // Translating a translation: the Sanskrit context would invite it
            // to answer from the original instead of the text it was given.
            : const VerseContext(),
      );
      repository.store.saveLocalTranslation(
        LocalTranslation(
          packId: work.pack.packId,
          workSlug: work.slug,
          ref: job.verse.ref,
          language: job.language.code,
          text: text,
          model: source.isOriginal
              ? assistant.model.fileName
              : '${assistant.model.fileName} via ${source.languageCode}',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Renders one explanation into another language. Never writes one: an
  /// explanation this app invented would be the model commenting on scripture
  /// out of its own memory, which is exactly what it does not do.
  Future<bool> _fillNote(_Job job) async {
    final source = chooseNoteSource(
      target: job.language,
      available: packNotes(job.verse),
    );
    if (source == null) return false;
    try {
      final progress = await translateNoteStream(
        assistant,
        note: source.text,
        from: source.languageName,
        language: job.language,
        about: '${work.title}, verse ${job.verse.label ?? job.verse.ref}',
      ).last;
      repository.store.saveLocalNote(
        LocalTranslation(
          packId: work.pack.packId,
          workSlug: work.slug,
          ref: job.verse.ref,
          language: job.language.code,
          text: progress.text,
          model: '${assistant.model.fileName} via ${source.languageCode}',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }
}

/// The explanations the pack itself carries, by language, ready to render
/// from. One of this phone's own would be a translation of a translation,
/// twice removed from the person who wrote it.
Map<String, String> packNotes(PassageView verse) {
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
