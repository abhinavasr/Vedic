import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/transliteration.dart';
import '../../library/scripture_repository.dart';
import '../reader_screens.dart';
import '../search_screen.dart';
import '../simple_screens.dart';
import '../theme.dart';
import 'hero_painter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.onOpenLibrary,
    required this.onOpenSettings,
    this.problem,
  });

  final ScriptureRepository repository;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSettings;

  /// Why bundled content couldn't be installed, if it couldn't.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final verse = repository.verseOfTheDay(DateTime.now());
    final heroHeight = math.max(
      380.0,
      MediaQuery.sizeOf(context).height * 0.44,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SingleChildScrollView(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: _Hero(onOpenSettings: onOpenSettings),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: heroHeight - 64),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _VerseCard(
                    verse: verse,
                    onRead: verse == null
                        ? null
                        : () => openVerseSection(context, repository, verse),
                  ),
                ),
                if (problem case final problem?)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text("Couldn't install bundled scripture"),
                      subtitle: Text(problem),
                    ),
                  ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _FeatureTiles(onOpenLibrary: onOpenLibrary),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SearchBar(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SearchScreen(repository: repository),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const _QuoteCard(),
                const SizedBox(height: 40),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];
    final soft = Colors.white.withValues(alpha: 0.85);
    return CustomPaint(
      painter: const HeroPainter(fadeTo: SadhanaColors.background),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'ॐ',
                    style: TextStyle(
                      fontSize: 44,
                      height: 1.1,
                      color: Color(0xFFE2BE86),
                      shadows: shadow,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sadhana',
                          style: serif(
                            size: 30,
                            color: Colors.white,
                          ).copyWith(shadows: shadow),
                        ),
                        Text(
                          'Scripture  ·  Calendar  ·  Self',
                          style: TextStyle(
                            fontSize: 14,
                            color: soft,
                            shadows: shadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: onOpenSettings,
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Text(
                'Ancient Wisdom\nfor a Calmer You',
                style: serif(
                  size: 34,
                  color: Colors.white,
                  height: 1.15,
                ).copyWith(shadows: shadow),
              ),
              const SizedBox(height: 10),
              Text(
                'Read  ·  Listen  ·  Reflect  ·  Anytime',
                style: TextStyle(fontSize: 15, color: soft, shadows: shadow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  const _VerseCard({required this.verse, required this.onRead});

  final VerseOfTheDay? verse;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final verse = this.verse;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SadhanaColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Verse of the Day',
                  style: TextStyle(fontSize: 15, color: SadhanaColors.inkSoft),
                ),
                const Spacer(),
                if (verse != null)
                  InkWell(
                    onTap: onRead,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${verse.work.title} ${verse.verse.label ?? verse.verse.ref}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: SadhanaColors.ink,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: SadhanaColors.inkSoft,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (verse == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Install a scripture pack to see a verse here each day.',
                  style: TextStyle(fontSize: 16, color: SadhanaColors.inkSoft),
                ),
              )
            else ...[
              Text(
                verse.verse.text,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.55,
                  color: SadhanaColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                devanagariToIast(verse.verse.text),
                style: serif(
                  size: 16,
                  style: FontStyle.italic,
                  color: SadhanaColors.inkSoft,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: _ListenButton()),
                  FilledButton.tonal(
                    onPressed: onRead,
                    style: FilledButton.styleFrom(
                      backgroundColor: SadhanaColors.greenTint,
                      foregroundColor: SadhanaColors.green,
                      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Read Full Verse', style: TextStyle(fontSize: 15)),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chant audio arrives as downloadable packs; until one is installed the
/// button explains that rather than doing nothing.
class _ListenButton extends StatelessWidget {
  const _ListenButton();

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(28),
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Chant audio isn't installed yet. It will arrive as a download.",
        ),
      ),
    ),
    child: const Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: SadhanaColors.green,
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
        ),
        SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Listen',
                style: TextStyle(fontSize: 16, color: SadhanaColors.ink),
              ),
              Text(
                'Sanskrit Chant',
                style: TextStyle(fontSize: 13, color: SadhanaColors.inkSoft),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FeatureTiles extends StatelessWidget {
  const _FeatureTiles({required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    void comingSoon(String title, IconData icon, String message) =>
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ComingSoonScreen(title: title, icon: icon, message: message),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Tile(
          title: 'Scriptures',
          subtitle: 'Read & Explore',
          icon: Icons.menu_book_outlined,
          background: const Color(0xFFFBEBD6),
          foreground: const Color(0xFFA0702A),
          onTap: onOpenLibrary,
        ),
        _Tile(
          title: 'Listen',
          subtitle: 'Chants & Audio',
          icon: Icons.headphones_outlined,
          background: const Color(0xFFFBE3DD),
          foreground: const Color(0xFFB5563E),
          onTap: () => comingSoon(
            'Listen',
            Icons.headphones_outlined,
            'Sanskrit chanting, verse by verse, arrives as downloadable audio packs.',
          ),
        ),
        _Tile(
          title: 'Panchang',
          subtitle: 'Calendar & Muhurat',
          icon: Icons.calendar_month_outlined,
          background: const Color(0xFFE4EFE0),
          foreground: const Color(0xFF4E7A45),
          onTap: () => comingSoon(
            'Panchang',
            Icons.calendar_month_outlined,
            'Tithi, nakṣatra, yoga, karaṇa and sunrise, calculated on this phone '
                'for where you are. Coming in a later update.',
          ),
        ),
        _Tile(
          title: 'Astrology',
          subtitle: 'Tithi & Planets',
          icon: Icons.auto_awesome_outlined,
          background: const Color(0xFFE9E6F7),
          foreground: const Color(0xFF5B4FA3),
          onTap: () => comingSoon(
            'Astrology',
            Icons.auto_awesome_outlined,
            'Planet positions and tithi details, calculated on this phone. '
                'Coming in a later update.',
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: foreground, size: 34),
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: SadhanaColors.ink,
                ),
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                color: SadhanaColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: SadhanaColors.searchFill,
    shape: const StadiumBorder(side: BorderSide(color: SadhanaColors.line)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.search, color: SadhanaColors.inkSoft, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search scriptures, verses or ask a question…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: serif(size: 16, color: SadhanaColors.inkSoft),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard();

  @override
  Widget build(BuildContext context) {
    final rule = SizedBox(
      width: 48,
      child: Divider(color: SadhanaColors.gold.withValues(alpha: 0.5)),
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            rule,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '“',
                style: serif(size: 44, color: SadhanaColors.gold, height: 0.9),
              ),
            ),
            rule,
          ],
        ),
        const Text(
          'धर्मो रक्षति रक्षितः ।',
          style: TextStyle(fontSize: 24, color: SadhanaColors.ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Dharma protects those who protect it.',
          style: TextStyle(fontSize: 15, color: SadhanaColors.inkSoft),
        ),
        const SizedBox(height: 16),
        Container(
          width: 72,
          height: 1.5,
          color: SadhanaColors.gold.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}
