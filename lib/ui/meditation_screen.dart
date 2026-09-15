import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../meditation/meditation_session.dart';
import 'home/hero_painter.dart';
import 'theme.dart';

const _totalMinutes = [5, 10, 20, 30];
const _intervalMinutes = <int?>[null, 1, 2, 5, 10];

class MeditationScreen extends StatefulWidget {
  const MeditationScreen({super.key});

  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen> {
  var _total = const Duration(minutes: 20);
  Duration? _interval = const Duration(minutes: 5);
  var _endingBell = true;
  MeditationSession? _session;
  Timer? _ticker;
  _Bells? _bells;

  /// Whether the ending bell is ringing and waiting to be stopped.
  var _ringing = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _bells?.dispose();
    unawaited(_keepAwake(false));
    super.dispose();
  }

  bool get _locked {
    final phase = _session?.phase;
    return phase == MeditationPhase.running || phase == MeditationPhase.paused;
  }

  /// Applies a settings change and discards a finished session, so the dial
  /// shows the new time.
  void _change(void Function() change) {
    _stopBell();
    setState(() {
      change();
      _session = null;
    });
  }

  void _start() {
    _stopBell();
    _bells ??= _Bells();
    setState(
      () => _session = MeditationSession(
        MeditationSettings(
          total: _total,
          interval: _interval,
          endingBell: _endingBell,
        ),
      )..start(DateTime.now()),
    );
    _runTicker();
  }

  void _runTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    unawaited(_keepAwake(true));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_keepAwake(false));
  }

  void _tick() {
    final session = _session;
    if (session == null) return;
    for (final sound in session.tick(DateTime.now())) {
      switch (sound) {
        case MeditationSound.chime:
          unawaited(_bells?.chime());
        case MeditationSound.endingBell:
          _ringing = true;
          unawaited(_bells?.ringUntilStopped());
      }
    }
    if (session.phase == MeditationPhase.finished) {
      _stopTicker();
      unawaited(HapticFeedback.mediumImpact());
    }
    setState(() {});
  }

  void _pause() {
    _session?.pause(DateTime.now());
    _stopTicker();
    setState(() {});
  }

  void _resume() {
    _session?.resume(DateTime.now());
    _runTicker();
    setState(() {});
  }

  void _end() {
    _stopTicker();
    _stopBell();
    setState(() => _session = null);
  }

  void _stopBell() {
    if (!_ringing) return;
    unawaited(_bells?.stop());
    setState(() => _ringing = false);
  }

  Future<void> _keepAwake(bool on) async {
    try {
      await (on ? WakelockPlus.enable() : WakelockPlus.disable());
    } on Exception {
      // Only the display dims; the session is timed by the clock regardless.
    }
  }

  Future<void> _pickCustom() async {
    var minutes = _total.inMinutes.clamp(1, 120).toDouble();
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Custom time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${minutes.round()} min', style: serif(size: 32)),
              Slider(
                value: minutes,
                min: 1,
                max: 120,
                divisions: 119,
                activeColor: SadhanaColors.green,
                onChanged: (v) => setDialog(() => minutes = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, minutes.round()),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      _change(() => _total = Duration(minutes: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final now = DateTime.now();
    final phase = session?.phase ?? MeditationPhase.ready;
    final remaining = session?.remaining(now) ?? _total;
    final progress = session == null
        ? 0.0
        : 1 - remaining.inMilliseconds / session.settings.total.inMilliseconds;
    final isCustom = !_totalMinutes.contains(_total.inMinutes);
    final locked = _locked;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: SingleChildScrollView(
        child: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 380,
              child: CustomPaint(
                painter: HeroPainter(
                  fadeTo: SadhanaColors.background,
                  light: true,
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meditation Timer',
                            style: serif(size: 36, color: SadhanaColors.ink),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 44,
                            height: 2,
                            color: SadhanaColors.gold,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'A simple space to sit, breathe,\nand return within.',
                            style: serif(
                              size: 18,
                              color: SadhanaColors.inkSoft,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
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
                        padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: _TimerDial(
                                remaining: remaining,
                                progress: progress,
                                status: switch (phase) {
                                  MeditationPhase.ready => 'Ready to begin',
                                  MeditationPhase.running => 'Breathe',
                                  MeditationPhase.paused => 'Paused',
                                  MeditationPhase.finished =>
                                    'Session complete',
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                            const _SettingTitle(
                              icon: Icons.schedule,
                              title: 'Total Time',
                              subtitle:
                                  "Choose how long you'd like to meditate.",
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final minutes in _totalMinutes)
                                  _Choice(
                                    label: '$minutes min',
                                    selected: _total.inMinutes == minutes,
                                    onTap: locked
                                        ? null
                                        : () => _change(
                                            () => _total = Duration(
                                              minutes: minutes,
                                            ),
                                          ),
                                  ),
                                _Choice(
                                  label: isCustom
                                      ? '${_total.inMinutes} min'
                                      : 'Custom',
                                  selected: isCustom,
                                  onTap: locked ? null : _pickCustom,
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const _SettingTitle(
                              icon: Icons.notifications_none,
                              title: 'Interval Chime',
                              subtitle:
                                  'Play a gentle chime during your meditation.',
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final minutes in _intervalMinutes)
                                  _Choice(
                                    label: minutes == null
                                        ? 'Off'
                                        : '$minutes min',
                                    selected: _interval?.inMinutes == minutes,
                                    onTap: locked
                                        ? null
                                        : () => _change(
                                            () => _interval = minutes == null
                                                ? null
                                                : Duration(minutes: minutes),
                                          ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Expanded(
                                  child: _SettingTitle(
                                    icon: Icons.notifications_active_outlined,
                                    title: 'Ending Bell',
                                    subtitle:
                                        'Ring the bell until you stop it when '
                                        'the session ends.',
                                  ),
                                ),
                                Switch(
                                  value: _endingBell,
                                  trackColor: WidgetStateProperty.resolveWith(
                                    (states) =>
                                        states.contains(WidgetState.selected)
                                        ? SadhanaColors.green
                                        : null,
                                  ),
                                  onChanged: locked
                                      ? null
                                      : (on) => _change(() => _endingBell = on),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            _controls(phase),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Center(
                      child: Text(
                        '“A quieter mind, a kinder you.”',
                        style: serif(
                          size: 18,
                          style: FontStyle.italic,
                          color: SadhanaColors.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(MeditationPhase phase) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final primary = FilledButton.styleFrom(
      backgroundColor: SadhanaColors.green,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      shape: shape,
      textStyle: serif(size: 20),
    );
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: SadhanaColors.green,
      minimumSize: const Size.fromHeight(56),
      side: const BorderSide(color: SadhanaColors.green),
      shape: shape,
      textStyle: serif(size: 20),
    );

    Widget pair(String label, IconData icon, VoidCallback action) => Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: secondary,
            onPressed: action,
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: primary,
            onPressed: _end,
            child: const Text('End'),
          ),
        ),
      ],
    );

    if (_ringing) {
      return FilledButton.icon(
        style: primary,
        onPressed: _stopBell,
        icon: const Icon(Icons.notifications_off_outlined, size: 28),
        label: const Text('Stop Bell'),
      );
    }
    return switch (phase) {
      MeditationPhase.ready || MeditationPhase.finished => FilledButton.icon(
        style: primary,
        onPressed: _start,
        icon: const Icon(Icons.play_circle_fill, size: 30),
        label: Text(
          phase == MeditationPhase.ready ? 'Start Meditation' : 'Begin Again',
        ),
      ),
      MeditationPhase.running => pair('Pause', Icons.pause, _pause),
      MeditationPhase.paused => pair('Resume', Icons.play_arrow, _resume),
    };
  }
}

/// The temple bell: once for an interval chime, and on repeat at the end of
/// a session until stopped.
class _Bells {
  final _chime = AudioPlayer();
  final _ending = AudioPlayer();

  static final _bell = AssetSource('sounds/bell_temple.m4a');

  Future<void> chime() => _quietly(() async {
    await _chime.stop();
    await _chime.play(_bell);
  });

  Future<void> ringUntilStopped() => _quietly(() async {
    await _chime.stop();
    await _ending.setReleaseMode(ReleaseMode.loop);
    await _ending.play(_bell);
  });

  Future<void> stop() => _quietly(() async {
    await _ending.stop();
    await _chime.stop();
  });

  void dispose() {
    unawaited(_chime.dispose());
    unawaited(_ending.dispose());
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      // Sound is best-effort: a failed bell must never break the timer.
    }
  }
}

class _TimerDial extends StatelessWidget {
  const _TimerDial({
    required this.remaining,
    required this.progress,
    required this.status,
  });

  final Duration remaining;
  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final clock =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return SizedBox.square(
      dimension: 250,
      child: CustomPaint(
        painter: _DialPainter(progress),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.spa_outlined,
                color: SadhanaColors.gold,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                clock,
                style: serif(
                  size: 60,
                  color: SadhanaColors.ink,
                  height: 1,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: serif(size: 17, color: SadhanaColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    canvas
      ..drawCircle(center, radius + 6, Paint()..color = const Color(0xFFF6F2EB))
      ..drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = SadhanaColors.green.withValues(
            alpha: progress > 0 ? 0.25 : 1,
          ),
      );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = SadhanaColors.green,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SettingTitle extends StatelessWidget {
  const _SettingTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: const Color(0xFFA0702A), size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: serif(size: 20, color: SadhanaColors.ink)),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
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

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Opacity(
      opacity: onTap == null && !selected ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? SadhanaColors.green : const Color(0xFFF3EFE8),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: selected ? Colors.white : SadhanaColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
