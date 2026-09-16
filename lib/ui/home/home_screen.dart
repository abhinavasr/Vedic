import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/assistant.dart';
import '../../ai/verse_judgement.dart';
import '../../core/transliteration.dart';
import '../../library/scripture_repository.dart';
import '../brand_header.dart';
import '../listen_meaning.dart';
import '../reader_screens.dart';
import '../simple_screens.dart';
import '../theme.dart';
import 'hero_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.onOpenLibrary,
    required this.onOpenMeditation,
    required this.onOpenSettings,
    required this.onOpenChants,
    this.problem,
  });

  final ScriptureRepository repository;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenMeditation;
  final VoidCallback onOpenSettings;

  /// Opens the reader with the chant playing.
  final VoidCallback onOpenChants;

  /// Why bundled content couldn't be installed, if it couldn't.
  final String? problem;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Fires at the next five in the morning, so a phone left open overnight
  /// shows the new verse without being reopened.
  Timer? _turnover;

  /// The pass working out which of the coming days' verses are worth showing.
  Future<void>? _judging;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waitForTomorrow();
    Assistant.instance.state.addListener(_judgeAhead);
    _judgeAhead();
  }

  @override
  void dispose() {
    _turnover?.cancel();
    Assistant.instance.state.removeListener(_judgeAhead);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Works out, in advance, which of the coming days' verses say something on
  /// their own.
  ///
  /// Ahead rather than now: a verse that changed a second after it appeared
  /// would be worse than the wrong verse. Today is shown from what is already
  /// known, and what is learned here is for tomorrow. With no model installed
  /// nothing is judged and every verse is eligible, which is how it worked
  /// before there was a model at all.
  void _judgeAhead() {
    if (_judging != null) return;
    _judging = _judgeTheDaysAhead().whenComplete(() => _judging = null);
  }

  Future<void> _judgeTheDaysAhead() async {
    final assistant = Assistant.instance;
    if (!assistant.state.value.canAnswer) return;
    final store = widget.repository.store;
    for (var ahead = 1; ahead <= 2; ahead++) {
      final day = DateTime.now().add(Duration(days: ahead));
      for (final candidate in widget.repository.versesForDay(day)) {
        if (!mounted) return;
        final work = candidate.work;
        final known = store.standsAlone(
          work.pack.packId,
          work.slug,
          candidate.verse.ref,
        );
        // Settled: that day has its verse, or this one is already ruled out
        // and the next in line is the one to look at.
        if (known == true) break;
        if (known == false) continue;
        final verdict = await judgeStandalone(
          assistant,
          verse: candidate.verse.text,
          meaning: candidate.verse.translationFor(const ['en', 'hi'])?.text,
          about: '${work.title}, verse '
              '${candidate.verse.label ?? candidate.verse.ref}',
        );
        // No answer is not a no: leave the day as it stands and try again
        // another time rather than passing over a verse on a shrug.
        if (verdict == null) break;
        store.saveStandsAlone(
          packId: work.pack.packId,
          workSlug: work.slug,
          ref: candidate.verse.ref,
          stands: verdict,
        );
        if (verdict) break;
      }
    }
  }

  /// Verses already found to say nothing on their own.
  bool _passedOver(VerseOfTheDay candidate) =>
      widget.repository.store.standsAlone(
        candidate.work.pack.packId,
        candidate.work.slug,
        candidate.verse.ref,
      ) ==
      false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A sleeping phone does not run its timers. Coming back to the app is the
    // other way the day changes, and the more common one.
    if (state == AppLifecycleState.resumed) _turnTheDay();
  }

  void _turnTheDay() {
    if (!mounted) return;
    setState(_waitForTomorrow);
  }

  /// Sets the alarm for the next turnover, in the device's own local time.
  void _waitForTomorrow() {
    _turnover?.cancel();
    final now = DateTime.now();
    final wait = nextScriptureDay(now).difference(now);
    _turnover = Timer(wait.isNegative ? Duration.zero : wait, _turnTheDay);
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final problem = widget.problem;
    final onOpenLibrary = widget.onOpenLibrary;
    final onOpenMeditation = widget.onOpenMeditation;
    final onOpenSettings = widget.onOpenSettings;
    final onOpenChants = widget.onOpenChants;
    final verse = repository.verseOfTheDay(DateTime.now(), skip: _passedOver);
    // Only the header sits on the picture now, so the banner is as tall as
    // it needs to be to read as one rather than as a gap.
    final heroHeight = math.max(
      260.0,
      MediaQuery.sizeOf(context).height * 0.32,
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
              child: HeroBackground(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [SadhanaHeader(onOpenSettings: onOpenSettings)],
                    ),
                  ),
                ),
              ),
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
                  child: _FeatureTiles(
                    onOpenChants: onOpenChants,
                    onOpenLibrary: onOpenLibrary,
                    onOpenMeditation: onOpenMeditation,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ],
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
                  size: 15,
                  style: FontStyle.italic,
                  color: SadhanaColors.inkSoft,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              // One under the other. Side by side, the two of them squeezed
              // the listen row until it broke a word across every line.
              ListenControl(
                verse: verse.verse,
                // The chips belong beside the verse they apply to, in the
                // reader. This card is one verse and one button.
                compact: true,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onRead,
                  style: FilledButton.styleFrom(
                    backgroundColor: SadhanaColors.greenTint,
                    foregroundColor: SadhanaColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureTiles extends StatelessWidget {
  const _FeatureTiles({
    required this.onOpenLibrary,
    required this.onOpenMeditation,
    required this.onOpenChants,
  });

  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenMeditation;
  final VoidCallback onOpenChants;

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
          // Straight to the chant, now that there is one. It opens where the
          // reader left off, with the chant switched on for the verse they
          // land on.
          onTap: onOpenChants,
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
            'Tithi, nakṣatra, yoga, karaṇa and sunrise, calculated on this '
                'phone for where you are. Coming in a later update.',
          ),
        ),
        _Tile(
          title: 'Meditation',
          subtitle: 'Calm & Mindfulness',
          icon: Icons.self_improvement,
          background: const Color(0xFFE9E6F7),
          foreground: const Color(0xFF5B4FA3),
          onTap: onOpenMeditation,
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
