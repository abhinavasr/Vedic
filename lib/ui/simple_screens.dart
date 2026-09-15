import 'package:flutter/material.dart';

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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: ListView(
      children: [
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
