import 'package:flutter/material.dart';

import '../ai/reading_languages.dart';
import '../notify/daily_verse.dart';

import 'ai/assistant_screen.dart';
import 'settings/language_screen.dart';
import 'theme.dart';

/// A feature that isn't available yet, explained rather than broken.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: SadhanaColors.gold),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: SadhanaColors.inkSoft,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.translate_outlined),
          title: const Text('Reading language'),
          // Through the scope, not the singleton: read directly, this row kept
          // showing the language that was set when it was first drawn.
          subtitle: Text(ReadingLanguageScope.of(context).language.name),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
            );
          },
        ),
        const Divider(height: 1),
        // Off until asked for, and off again the moment it is not wanted.
        if (DailyVerseNotice.instance case final notice?)
          SwitchListTile(
            key: const ValueKey('daily-verse-notice'),
            secondary: const Icon(Icons.notifications_none),
            value: notice.enabled,
            onChanged: (on) async {
              await notice.set(on: on);
              if (mounted) setState(() {});
            },
            title: const Text('A verse each morning'),
            subtitle: const Text(
              'A quiet notice at five, when the day’s verse changes',
            ),
          ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('On-device AI'),
          subtitle: const Text(
            'Translate verses and ask questions, all on this phone',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AssistantScreen()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open source licences'),
          onTap: () =>
              showLicensePage(context: context, applicationName: 'Sadhana'),
        ),
        const AboutListTile(
          icon: Icon(Icons.info_outline),
          applicationName: 'Sadhana',
          aboutBoxChildren: [
            Text(
              'Scripture, calendar and self-study. Everything runs on this phone.',
            ),
          ],
        ),
      ],
    ),
  );
}
