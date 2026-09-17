import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../panchang/panchang.dart';
import '../panchang/device_place.dart';
import '../panchang/place.dart';
import '../panchang/rise_set.dart';
import '../panchang/today.dart';
import 'brand_header.dart';
import 'home/hero_background.dart';
import 'theme.dart';

/// The day's panchang, computed on this phone.
///
/// No festivals. Tithi and sunrise are astronomy and come out the same for
/// everybody; festival dates are convention, and two accurate panchangs
/// legitimately disagree about them. They need a rule engine with a tradition
/// setting behind it, and until that exists it is better to show nothing than
/// to show a date this app cannot stand behind.
class PanchangScreen extends StatefulWidget {
  const PanchangScreen({super.key, required this.onOpenSettings, this.place});

  final VoidCallback onOpenSettings;

  /// Where to compute for. Normally found from the device's own timezone.
  final Place? place;

  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

class _PanchangScreenState extends State<PanchangScreen> {
  late Future<DayPanchang> _day = _compute(DateTime.now());
  var _offset = 0;

  Future<DayPanchang> _compute(DateTime day) async {
    final place = widget.place ?? await devicePlace();
    return panchangFor(day, place);
  }

  void _go(int days) {
    setState(() {
      _offset += days;
      _day = _compute(DateTime.now().add(Duration(days: _offset)));
    });
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    // A Scaffold, because this is pushed as its own route and does not inherit
    // the shell's. Without one there is no Material above the text, and
    // Flutter draws it as it draws any unstyled text — yellow double
    // underlines on black, which is the framework saying "no theme here"
    // rather than anything this screen asked for.
    child: Scaffold(
      backgroundColor: SadhanaColors.background,
      body: FutureBuilder<DayPanchang>(
        future: _day,
        builder: (context, snapshot) {
          final day = snapshot.data;
          return SingleChildScrollView(
          child: Stack(
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 300,
                child: HeroBackground(child: SizedBox.expand()),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                      child: SadhanaHeader(
                        onOpenSettings: widget.onOpenSettings,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _Title(),
                  ),
                  const SizedBox(height: 18),
                  if (day == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _DayCard(
                        day: day,
                        onEarlier: () => _go(-1),
                        onLater: () => _go(1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _LimbsCard(day: day),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SkyCard(day: day),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _TimingsCard(day: day),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _Convention(day: day),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Panchang', style: serif(size: 40, color: SadhanaColors.ink)),
      const SizedBox(height: 8),
      Container(width: 54, height: 2, color: SadhanaColors.gold),
      const SizedBox(height: 12),
      const Text(
        'Sacred timings and lunar reckoning,\ncalculated on this phone.',
        style: TextStyle(fontSize: 15, height: 1.5, color: SadhanaColors.ink),
      ),
    ],
  );
}

/// The date, the moon, and the way to other days.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.onEarlier,
    required this.onLater,
  });

  final DayPanchang day;
  final VoidCallback onEarlier;
  final VoidCallback onLater;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('panchang-earlier'),
          onPressed: onEarlier,
          icon: const Icon(Icons.chevron_left),
          color: SadhanaColors.inkSoft,
          tooltip: 'The day before',
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                day.vara.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: SadhanaColors.gold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day.day} ${_months[day.day.month - 1]} ${day.day.year}',
                style: serif(size: 22, color: SadhanaColors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                '${day.moonPhaseName}  ·  ${day.masa}  ·  ${day.paksha.label}',
                style: const TextStyle(
                  fontSize: 13,
                  color: SadhanaColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
        _MoonDisc(lit: day.moonPhase, waxing: day.paksha == Paksha.shukla),
        IconButton(
          key: const ValueKey('panchang-later'),
          onPressed: onLater,
          icon: const Icon(Icons.chevron_right),
          color: SadhanaColors.inkSoft,
          tooltip: 'The day after',
        ),
      ],
    ),
  );
}

/// The moon as it looks tonight, drawn rather than listed.
class _MoonDisc extends StatelessWidget {
  const _MoonDisc({required this.lit, required this.waxing});

  final double lit;
  final bool waxing;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 42,
    child: CustomPaint(painter: _MoonPainter(lit: lit, waxing: waxing)),
  );
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter({required this.lit, required this.waxing});

  final double lit;
  final bool waxing;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = const Color(0xFF2A2A30),
    );
    // The terminator is an ellipse whose width follows the lit fraction.
    final light = Paint()..color = const Color(0xFFF3ECDD);
    final width = (2 * lit - 1).abs() * radius;
    final half = Path()
      ..addArc(
        Rect.fromCircle(center: centre, radius: radius),
        waxing ? -1.5708 : 1.5708,
        3.14159,
      )
      ..close();
    canvas.drawPath(half, light);
    final terminator = Path()
      ..addOval(
        Rect.fromCenter(center: centre, width: width * 2, height: radius * 2),
      );
    canvas.drawPath(
      terminator,
      Paint()..color = lit > 0.5 ? light.color : const Color(0xFF2A2A30),
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) =>
      old.lit != lit || old.waxing != waxing;
}

/// The five limbs, each with when it gives way.
class _LimbsCard extends StatelessWidget {
  const _LimbsCard({required this.day});

  final DayPanchang day;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardTitle('Today’s Panchang', icon: Icons.brightness_5_outlined),
        const SizedBox(height: 14),
        _LimbRow(
          label: 'Tithi',
          limb: day.tithi,
          day: day.day,
          paksha: day.paksha.label,
        ),
        _LimbRow(label: 'Nakṣatra', limb: day.nakshatra, day: day.day),
        _LimbRow(label: 'Yoga', limb: day.yoga, day: day.day),
        _LimbRow(label: 'Karaṇa', limb: day.karana, day: day.day),
        _PlainRow(label: 'Pakṣa', value: day.paksha.label),
        _PlainRow(label: 'Māsa', value: day.masa),
      ],
    ),
  );
}

class _LimbRow extends StatelessWidget {
  const _LimbRow({
    required this.label,
    required this.limb,
    required this.day,
    this.paksha,
  });

  final String label;
  final Limb limb;

  /// The day being shown, so a boundary that falls on another one says so.
  final DateTime day;
  final String? paksha;

  @override
  Widget build(BuildContext context) {
    final ends = limb.endsAt?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: SadhanaColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  limb.name,
                  style: const TextStyle(
                    fontSize: 15,
                    color: SadhanaColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (ends != null)
                  Text(
                    // A tithi can run past midnight — printed panchangs say
                    // "upto full night" for it — and "until 8:31 AM" with no
                    // day is a different claim from the one the maths makes.
                    'until ${clockTime(ends)}${_dayOf(ends, day)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SadhanaColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: SadhanaColors.inkSoft),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: SadhanaColors.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// Sunrise, sunset, moonrise, moonset.
class _SkyCard extends StatelessWidget {
  const _SkyCard({required this.day});

  final DayPanchang day;

  @override
  Widget build(BuildContext context) {
    if (!day.hasSunrise) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle('The Sun', icon: Icons.wb_twilight),
            const SizedBox(height: 10),
            Text(
              day.sun.state == SkyState.always
                  ? 'The Sun does not set here today. Everything reckoned from '
                        'sunrise waits for it to return.'
                  : 'The Sun does not rise here today. Everything reckoned '
                        'from sunrise waits for it to return.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: SadhanaColors.inkSoft,
              ),
            ),
          ],
        ),
      );
    }
    return _Card(
      child: Row(
        children: [
          _SkyTime(
            label: 'Sunrise',
            at: day.sun.rise,
            icon: Icons.wb_sunny_outlined,
            colour: SadhanaColors.gold,
          ),
          _SkyTime(
            label: 'Sunset',
            at: day.sun.set,
            icon: Icons.wb_twilight,
            colour: SadhanaColors.gold,
          ),
          _SkyTime(
            label: 'Moonrise',
            at: day.moon.rise,
            icon: Icons.nightlight_outlined,
            colour: SadhanaColors.green,
          ),
          _SkyTime(
            label: 'Moonset',
            at: day.moon.set,
            icon: Icons.nightlight_round,
            colour: SadhanaColors.green,
          ),
        ],
      ),
    );
  }
}

class _SkyTime extends StatelessWidget {
  const _SkyTime({
    required this.label,
    required this.at,
    required this.icon,
    required this.colour,
  });

  final String label;
  final DateTime? at;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 22, color: colour),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: SadhanaColors.inkSoft),
        ),
        const SizedBox(height: 4),
        Text(
          // The Moon skips a day about once a month, which is worth saying
          // rather than leaving blank.
          at == null ? '—' : clockTime(at!.toLocal()),
          style: const TextStyle(
            fontSize: 15,
            color: SadhanaColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// The windows of the day: the two worth keeping, and the three worth avoiding.
class _TimingsCard extends StatelessWidget {
  const _TimingsCard({required this.day});

  final DayPanchang day;

  @override
  Widget build(BuildContext context) {
    if (day.auspicious.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('Timings', icon: Icons.schedule),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final part in day.auspicious)
                _PartChip(part: part, good: true),
              for (final part in day.inauspicious)
                _PartChip(part: part, good: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartChip extends StatelessWidget {
  const _PartChip({required this.part, required this.good});

  final DayPart part;
  final bool good;

  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: good ? SadhanaColors.greenTint : const Color(0xFFFBEFE6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          part.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: good ? SadhanaColors.green : const Color(0xFF9A5B33),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${clockTime(part.from.toLocal())} – '
          '${clockTime(part.to.toLocal())}',
          style: const TextStyle(fontSize: 13, color: SadhanaColors.ink),
        ),
      ],
    ),
  );
}

/// Which conventions produced this page.
///
/// Not a footnote for the sake of it: a reader comparing this with the
/// panchang their family uses needs to know which ayanāṃśa and which month
/// reckoning it was computed with, because that is usually the whole of the
/// disagreement.
class _Convention extends StatelessWidget {
  const _Convention({required this.day});

  final DayPanchang day;

  @override
  Widget build(BuildContext context) => Text(
    'Computed on this phone for ${day.place.city} · '
    '${day.ayana.label} ayanāṃśa · '
    '${day.purnimanta ? 'Pūrṇimānta' : 'Amānta'} months · '
    'sunrise at the sea-level horizon.',
    style: const TextStyle(
      fontSize: 12,
      height: 1.5,
      color: SadhanaColors.inkSoft,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    decoration: BoxDecoration(
      color: SadhanaColors.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x11000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: SadhanaColors.gold),
      const SizedBox(width: 10),
      Text(text, style: serif(size: 19, color: SadhanaColors.ink)),
    ],
  );
}

/// Which day a boundary falls on, where it is not the one being shown.
String _dayOf(DateTime at, DateTime day) {
  final difference = DateTime(at.year, at.month, at.day)
      .difference(DateTime(day.year, day.month, day.day))
      .inDays;
  return switch (difference) {
    0 => '',
    1 => ' tomorrow',
    -1 => ' yesterday',
    _ => ' on ${at.day}/${at.month}',
  };
}

/// A time as a reader reads it, in their own clock's convention.
String clockTime(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}
