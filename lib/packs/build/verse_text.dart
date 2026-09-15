import 'pack_builder.dart';

/// Parses scripture laid out as on sanskritdocuments.org, which is the layout
/// of the Bhagavad Gita source:
///
/// ```text
/// अथ प्रथमोऽध्यायः ।   अर्जुनविषादयोगः          chapter heading and title
///         धृतराष्ट्र उवाच ।                     speaker line
/// धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
/// मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥ १-१॥   verse ending in ॥ chapter-verse ॥
/// ... नाम प्रथमोऽध्यायः ॥ १॥                    colophon ending in ॥ chapter ॥
/// ```
///
/// Refs: verses `1.1`, speaker lines `1.1.speaker` (for the verse they
/// introduce), chapter openings `1.opening`, colophons `1.colophon`, and
/// `invocation` / `closing` for text before the first chapter and after the
/// last colophon. A parenthesised reading after a line is kept as a variant
/// rendering, never as verse text. A speaker line that falls inside a verse
/// (the speaker changes mid-verse, as in Gita 1.21) stays in that verse's
/// text, because it is recited there.
///
/// Strict by design: anything that doesn't fit throws a [FormatException]
/// with its line number, so no text is silently dropped or misfiled.
List<PassageSource> passagesFromVerseText(String text) =>
    _VerseParser(text.replaceAll('\r\n', '\n').split('\n')).parse();

final _heading = RegExp(r'^अथ\s?\S*ऽध्यायः\s*।\s*(\S.*)$');
final _speaker = RegExp(r'(?:उवाच|ुवाच)\s*।$');
final _verseEnd = RegExp(r'॥\s*([०-९0-9]+)-([०-९0-9]+)\s*॥\s*(.*)$');
final _chapterEnd = RegExp(r'॥\s*([०-९0-9]+)\s*॥$');
final _trailingVariant = RegExp(r'\s*\(([^()]+)\)$');

class _VerseParser {
  _VerseParser(this._lines);

  final List<String> _lines;
  final _passages = <PassageSource>[];
  final _pending = <String>[];
  final _variants = <String>[];
  var _pendingFrom = 0;
  SectionSource? _chapter;
  var _chapterNumber = 0;
  var _chapterClosed = false;
  int? _lastVerse;
  String? _speakerLine;

  List<PassageSource> parse() {
    for (var i = 0; i < _lines.length; i++) {
      final lineNo = i + 1;
      final line = _lines[i].trim();
      if (line.isEmpty) continue;

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        _startChapter(lineNo, line, heading[1]!.trim());
        continue;
      }

      final inChapter = _chapter != null && !_chapterClosed;
      if (inChapter &&
          _pending.isEmpty &&
          line.length <= 40 &&
          _speaker.hasMatch(line)) {
        if (_speakerLine != null) throw _error(lineNo, 'two speaker lines');
        _speakerLine = line;
        continue;
      }

      if (_pending.isEmpty) _pendingFrom = lineNo;

      final verseEnd = inChapter ? _verseEnd.firstMatch(line) : null;
      if (verseEnd != null) {
        _addVerse(lineNo, line, verseEnd);
        continue;
      }

      final chapterEnd = inChapter ? _chapterEnd.firstMatch(line) : null;
      if (chapterEnd != null) {
        _addColophon(lineNo, line, _number(chapterEnd[1]!));
        continue;
      }

      _addLine(line);
    }
    return _finish();
  }

  void _startChapter(int lineNo, String line, String title) {
    if (_speakerLine != null) {
      throw _error(lineNo, 'speaker line "$_speakerLine" has no verse');
    }
    if (_pending.isNotEmpty) {
      if (_chapter != null) {
        throw _error(
          _pendingFrom,
          'text before a chapter heading is not a verse',
        );
      }
      _passages.add(
        PassageSource(
          ref: 'invocation',
          kind: PassageKind.prose,
          text: _pending.join('\n'),
        ),
      );
      _clearPending(lineNo);
    }
    _chapterNumber++;
    _chapter = SectionSource(
      kind: 'chapter',
      number: '$_chapterNumber',
      title: title,
    );
    _chapterClosed = false;
    _lastVerse = null;
    _passages.add(
      PassageSource(
        ref: '$_chapterNumber.opening',
        kind: PassageKind.heading,
        text: line,
        section: _chapter,
      ),
    );
  }

  void _addVerse(int lineNo, String line, RegExpMatch end) {
    final chapter = _number(end[1]!);
    final verse = _number(end[2]!);
    if (chapter != _chapterNumber) {
      throw _error(
        lineNo,
        'verse $chapter.$verse is in chapter $_chapterNumber',
      );
    }
    if (_lastVerse != null && verse <= _lastVerse!) {
      throw _error(lineNo, 'verse $chapter.$verse is out of order');
    }

    _addLine(line.substring(0, end.start).trimRight());
    final after = end[3]!.trim();
    if (after.isNotEmpty) {
      final variant = RegExp(r'^\(([^()]+)\)$').firstMatch(after);
      if (variant == null) {
        throw _error(lineNo, 'unexpected text after the verse number: $after');
      }
      _variants.add(variant[1]!.trim());
    }

    final ref = '$chapter.$verse';
    if (_speakerLine != null) {
      _passages.add(
        PassageSource(
          ref: '$ref.speaker',
          kind: PassageKind.heading,
          text: _speakerLine!,
          section: _chapter,
        ),
      );
      _speakerLine = null;
    }
    _passages.add(
      PassageSource(
        ref: ref,
        label: ref,
        kind: PassageKind.verse,
        text: '${_pending.join('\n')} ॥',
        section: _chapter,
        renderings: [
          for (final variant in _variants)
            RenderingSource(
              kind: RenderingKind.variant,
              language: 'sa',
              script: 'Deva',
              text: variant,
            ),
        ],
      ),
    );
    _lastVerse = verse;
    _clearPending(lineNo);
  }

  void _addColophon(int lineNo, String line, int chapter) {
    if (chapter != _chapterNumber) {
      throw _error(
        lineNo,
        'colophon of chapter $chapter ends chapter $_chapterNumber',
      );
    }
    if (_speakerLine != null) {
      throw _error(lineNo, 'speaker line "$_speakerLine" has no verse');
    }
    _addLine(line);
    if (_variants.isNotEmpty) {
      throw _error(lineNo, 'variant reading inside a colophon');
    }
    _passages.add(
      PassageSource(
        ref: '$_chapterNumber.colophon',
        kind: PassageKind.prose,
        text: _pending.join('\n'),
        section: _chapter,
      ),
    );
    _chapterClosed = true;
    _clearPending(lineNo);
  }

  List<PassageSource> _finish() {
    if (_chapter == null) {
      throw const FormatException(
        'no chapter headings found (expected lines like "अथ प्रथमोऽध्यायः ।   …")',
      );
    }
    if (_speakerLine != null) {
      throw FormatException('speaker line "$_speakerLine" has no verse');
    }
    if (_pending.isNotEmpty) {
      if (!_chapterClosed) {
        throw _error(_pendingFrom, 'text after the last verse is not a verse');
      }
      if (_variants.isNotEmpty) {
        throw _error(_pendingFrom, 'variant reading in the closing text');
      }
      _passages.add(
        PassageSource(
          ref: 'closing',
          kind: PassageKind.prose,
          text: _pending.join('\n'),
        ),
      );
    }
    return _passages;
  }

  void _addLine(String line) {
    final variant = _trailingVariant.firstMatch(line);
    if (variant == null) {
      _pending.add(line);
      return;
    }
    _variants.add(variant[1]!.trim());
    _pending.add(line.substring(0, variant.start).trimRight());
  }

  void _clearPending(int lineNo) {
    _pending.clear();
    _variants.clear();
    _pendingFrom = lineNo + 1;
  }

  FormatException _error(int line, String message) =>
      FormatException('line $line: $message');
}

/// Parses ASCII or Devanagari digits.
int _number(String digits) => int.parse(
  String.fromCharCodes(
    digits.runes.map((r) => r >= 0x0966 && r <= 0x096F ? r - 0x0966 + 0x30 : r),
  ),
);
