import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'verse_reader.dart';

/// Opens a section: the verse reader where there are verses, the plain list
/// otherwise (an invocation, or a document's pages).
void openSection(
  BuildContext context,
  ScriptureRepository repository,
  WorkSummary work,
  SectionSummary section, {
  String? atRef,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => section.verseCount > 0
        ? VerseReaderScreen(
            repository: repository,
            work: work,
            section: section,
            initialRef: atRef,
          )
        : SectionScreen(repository: repository, work: work, section: section),
  ),
);

/// Opens the verse of the day, or a search hit, at that verse.
void openVerseSection(
  BuildContext context,
  ScriptureRepository repository,
  VerseOfTheDay verse,
) {
  final section = repository.sectionOf(verse.work, verse.sectionId);
  if (section == null) return;
  openSection(context, repository, verse.work, section, atRef: verse.verse.ref);
}

class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key, required this.repository, required this.work});

  final ScriptureRepository repository;
  final WorkSummary work;

  @override
  Widget build(BuildContext context) {
    final sections = repository.sections(work);
    return Scaffold(
      appBar: AppBar(title: Text(work.titleNative ?? work.title)),
      body: ListView.builder(
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final section = sections[i];
          final number = section.number;
          return ListTile(
            leading: CircleAvatar(child: Text(number ?? '·')),
            title: Text(
              section.title ??
                  (number == null ? 'Other text' : 'Chapter $number'),
            ),
            subtitle: Text(
              section.verseCount > 0
                  ? '${section.verseCount} verses'
                  : '${section.passageCount} passages',
            ),
            onTap: () => openSection(context, repository, work, section),
          );
        },
      ),
    );
  }
}

class SectionScreen extends StatelessWidget {
  const SectionScreen({
    super.key,
    required this.repository,
    required this.work,
    required this.section,
  });

  final ScriptureRepository repository;
  final WorkSummary work;
  final SectionSummary section;

  @override
  Widget build(BuildContext context) {
    final passages = repository.passages(work, section);
    return Scaffold(
      appBar: AppBar(title: Text(section.title ?? work.title)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: passages.length,
        itemBuilder: (context, i) => _PassageTile(passages[i]),
      ),
    );
  }
}

class _PassageTile extends StatelessWidget {
  const _PassageTile(this.passage);

  final PassageView passage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final framing =
        passage.ref.endsWith('.colophon') ||
        passage.ref == 'invocation' ||
        passage.ref == 'closing';

    return switch (passage.type) {
      PassageType.heading => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          passage.text,
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(color: colors.primary),
        ),
      ),
      PassageType.speaker => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          passage.text,
          style: text.titleSmall?.copyWith(color: colors.secondary),
        ),
      ),
      PassageType.verse => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              passage.text,
              style: text.titleLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                if (passage.label case final label?)
                  Text(
                    label,
                    style: text.labelMedium?.copyWith(color: colors.outline),
                  ),
                for (final variant in passage.variants)
                  Text(
                    'पाठभेद: $variant',
                    style: text.bodySmall?.copyWith(color: colors.outline),
                  ),
              ],
            ),
          ],
        ),
      ),
      PassageType.prose || PassageType.page => Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          passage.text,
          textAlign: framing ? TextAlign.center : TextAlign.start,
          style: text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
    };
  }
}
