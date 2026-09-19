import 'package:flutter/material.dart';

import '../library/quote_sources.dart';
import '../library/scripture_repository.dart';
import 'jump_sheet.dart';
import 'theme.dart';
import 'verse_reader.dart';

/// Opens a section: the verse reader where there are verses, the plain list
/// otherwise (an invocation, or a document's pages).
void openSection(
  BuildContext context,
  ScriptureRepository repository,
  WorkSummary work,
  SectionSummary section, {
  String? atRef,
  bool visiting = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => section.verseCount > 0
        ? VerseReaderScreen(
            repository: repository,
            work: work,
            section: section,
            initialRef: atRef,
            visiting: visiting,
          )
        : SectionScreen(repository: repository, work: work, section: section),
  ),
);

/// Opens the verse of the day, or a search hit, at that verse.
///
/// A visit, not a continuation: someone who taps the verse of the day is
/// being shown one verse of a book they may not be reading, and it must not
/// cost them the place they had reached in it.
void openVerseSection(
  BuildContext context,
  ScriptureRepository repository,
  VerseOfTheDay verse,
) {
  final section = repository.sectionOf(verse.work, verse.sectionId);
  if (section == null) return;
  openSection(
    context,
    repository,
    verse.work,
    section,
    atRef: verse.verse.ref,
    visiting: true,
  );
}

class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key, required this.repository, required this.work});

  final ScriptureRepository repository;
  final WorkSummary work;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  late final _quotes = QuoteSources(widget.repository.store);
  late var _isSource = _quotes.includes(widget.work);

  void _toggleSource(bool on) {
    _quotes.set(widget.work, on: on, all: widget.repository.works());
    setState(() => _isSource = on);
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final work = widget.work;
    final sections = repository.sections(work);
    return Scaffold(
      appBar: AppBar(title: Text(work.titleNative ?? work.title)),
      body: ListView.builder(
        // The switch rides at the top of the list, so it belongs to the book
        // it is about. It was in Settings, which meant somebody who wanted
        // the Ṛgveda in their mornings had to leave the Ṛgveda to say so.
        itemCount: sections.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                SwitchListTile(
                  key: const ValueKey('quote-source'),
                  value: _isSource,
                  onChanged: _toggleSource,
                  secondary: Icon(
                    _isSource
                        ? Icons.format_quote
                        : Icons.format_quote_outlined,
                    color: _isSource
                        ? SadhanaColors.gold
                        : SadhanaColors.inkSoft,
                  ),
                  title: const Text('Use for the verse of the day'),
                  subtitle: Text(
                    _isSource
                        ? 'A verse from here may open your morning'
                        : 'Not drawn on for the morning verse',
                    style: const TextStyle(color: SadhanaColors.inkSoft),
                  ),
                ),
                const Divider(height: 1),
              ],
            );
          }
          final section = sections[index - 1];
          final number = section.number;
          return ListTile(
            // Not a circle: a sūkta's number is "10.191", which a circle
            // sized for "2" cannot hold, and it spilled over the edge.
            leading: Container(
              width: 56,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: SadhanaColors.greenTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                number ?? '·',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: SadhanaColors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              section.title ??
                  (number == null
                      ? 'Other text'
                      : '${divisionName(section)} $number'),
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
