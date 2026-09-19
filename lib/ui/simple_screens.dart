import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/reading_languages.dart';
import '../audio/chant_audio.dart';
import '../library/scripture_repository.dart';
import '../notify/daily_verse.dart';

import 'ai/assistant_screen.dart';
import 'listen_meaning.dart';
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
  const ProfileScreen({super.key, this.repository});

  /// Needed by the settings that are about the books themselves. Null where
  /// settings is reached before anything is installed, and those rows then
  /// stay out rather than opening onto an empty list.
  final ScriptureRepository? repository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  CacheUsage? _chants;
  var _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    final source = ChantSource.instance;
    if (source.downloads == null) return;
    final usage = await source.downloads!.usage();
    if (mounted) setState(() => _chants = usage);
  }

  Future<void> _clearChants() async {
    final downloads = ChantSource.instance.downloads;
    if (downloads == null) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete downloaded chants?'),
        content: Text(
          'This frees ${_chants?.size ?? 'the space they use'}. Nothing is '
          'lost — any verse can be fetched again when you next play it, so '
          'long as you have a connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-chants'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    setState(() => _clearing = true);
    final freed = await downloads.clear();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _chants = const CacheUsage(bytes: 0, files: 0);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Freed ${freed.size}')));
  }

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
        // Hidden where there is nothing to manage: a build with no vault key
        // never downloads a chant, and a row reporting 0 bytes would only
        // raise a question it cannot answer.
        if (ChantSource.instance.downloads != null) ...[
          ListTile(
            key: const ValueKey('downloaded-chants'),
            leading: const Icon(Icons.graphic_eq_outlined),
            title: const Text('Downloaded chants'),
            subtitle: Text(switch (_chants) {
              null => 'Measuring…',
              final usage when usage.isEmpty =>
                'Nothing downloaded yet. Chants are kept as you play them.',
              final usage when usage.kept > 0 =>
                '${usage.size} · ${usage.files} recordings, '
                    '${usage.kept} kept for offline',
              final usage => '${usage.size} · ${usage.files} recordings',
            }),
            trailing: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: (_chants?.isEmpty ?? true) ? null : _clearChants,
                    child: const Text('Delete'),
                  ),
          ),
          const Divider(height: 1),
        ],
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
