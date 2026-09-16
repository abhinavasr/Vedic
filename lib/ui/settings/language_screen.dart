import 'package:flutter/material.dart';

import '../../ai/reading_languages.dart';
import '../../ai/translation.dart';
import '../theme.dart';

/// Picks the language the reader reads in.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key, this.reading});

  final ReadingLanguage? reading;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  ReadingLanguage get _reading => widget.reading ?? ReadingLanguage.instance;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SadhanaColors.background,
    appBar: AppBar(
      backgroundColor: SadhanaColors.background,
      foregroundColor: SadhanaColors.ink,
      elevation: 0,
      title: Text(
        'Reading language',
        style: serif(size: 22, color: SadhanaColors.ink),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Text(
            'Translations and explanations in this language are shown first. '
            'Where a pack does not carry one, the app can make it on this '
            'phone.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: SadhanaColors.inkSoft,
            ),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('speak-explanation'),
          value: _reading.withExplanation,
          onChanged: (on) => setState(() => _reading.withExplanation = on),
          title: const Text('Read the explanation too'),
          subtitle: const Text(
            'When a verse is read aloud, carry on into its explanation',
          ),
        ),
        const Divider(height: 1),
        RadioGroup<String>(
          groupValue: _reading.language.code,
          onChanged: (code) {
            if (code == null) return;
            final choice = TargetLanguage.forCode(code);
            if (choice != null) setState(() => _reading.language = choice);
          },
          child: Column(
            children: [
              for (final language in TargetLanguage.all)
                RadioListTile<String>(
                  key: ValueKey('language-${language.code}'),
                  value: language.code,
                  title: Text(language.name),
                  subtitle: language.endonym == language.name
                      ? null
                      : Text(language.endonym),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
