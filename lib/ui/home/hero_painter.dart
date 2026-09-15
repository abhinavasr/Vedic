import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dawn over mountain ridges with a temple silhouette, fading into the page
/// background. Painted rather than a photo so it costs no app size; swap in an
/// image asset later if the design calls for one.
class HeroPainter extends CustomPainter {
  const HeroPainter({required this.fadeTo});

  final Color fadeTo;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4E5E6E),
            Color(0xFF8D8C8E),
            Color(0xFFDDB07D),
            Color(0xFFF0D3A8),
          ],
          stops: [0, 0.38, 0.62, 0.8],
        ).createShader(rect),
    );

    final sun = Offset(size.width * 0.76, size.height * 0.52);
    final glow = Rect.fromCircle(center: sun, radius: size.width * 0.3);
    canvas
      ..drawCircle(
        sun,
        glow.width / 2,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xCCFFE3A3), Color(0x00FFE3A3)],
          ).createShader(glow),
      )
      ..drawCircle(sun, 9, Paint()..color = const Color(0xFFFFF5DA));

    _ridge(
      canvas,
      size,
      base: 0.54,
      amp: 0.1,
      seed: 1,
      color: const Color(0x8C6F7A86),
    );
    _ridge(
      canvas,
      size,
      base: 0.64,
      amp: 0.08,
      seed: 2,
      color: const Color(0xBF4B5563),
    );
    _temple(canvas, size);
    _ridge(
      canvas,
      size,
      base: 0.76,
      amp: 0.05,
      seed: 3,
      color: const Color(0xFF2F3A33),
    );

    final fade = Rect.fromLTWH(
      0,
      size.height * 0.7,
      size.width,
      size.height * 0.3,
    );
    canvas.drawRect(
      fade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fadeTo.withValues(alpha: 0), fadeTo],
        ).createShader(fade),
    );
  }

  void _ridge(
    Canvas canvas,
    Size size, {
    required double base,
    required double amp,
    required int seed,
    required Color color,
  }) {
    final path = Path()..moveTo(0, size.height);
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final wave =
          0.6 * math.sin(t * math.pi * (2 + seed) + seed) +
          0.4 * math.sin(t * math.pi * (5 + 2 * seed) + 1.7 * seed);
      path.lineTo(size.width * t, size.height * (base - amp * wave.abs()));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _temple(Canvas canvas, Size size) {
    final unit = size.width * 0.022;
    final cx = size.width * 0.86;
    final baseY = size.height * 0.68;
    final stone = Paint()..color = const Color(0xFF34302B);

    canvas
      ..drawRect(
        Rect.fromLTRB(
          cx - unit * 7,
          baseY - unit * 1.2,
          cx + unit * 6,
          baseY + unit * 4,
        ),
        stone,
      )
      ..drawRect(
        Rect.fromLTRB(
          cx - unit * 6.5,
          baseY - unit * 4,
          cx - unit * 1.5,
          baseY,
        ),
        stone,
      )
      ..drawPath(
        Path()
          ..moveTo(cx - unit * 7, baseY - unit * 4)
          ..lineTo(cx - unit * 4, baseY - unit * 7)
          ..lineTo(cx - unit, baseY - unit * 4)
          ..close(),
        stone,
      )
      ..drawPath(
        Path()
          ..moveTo(cx - unit * 2.5, baseY)
          ..lineTo(cx - unit * 2.5, baseY - unit * 5)
          ..quadraticBezierTo(
            cx - unit * 2.4,
            baseY - unit * 13,
            cx,
            baseY - unit * 17,
          )
          ..quadraticBezierTo(
            cx + unit * 2.4,
            baseY - unit * 13,
            cx + unit * 2.5,
            baseY - unit * 5,
          )
          ..lineTo(cx + unit * 2.5, baseY)
          ..close(),
        stone,
      )
      ..drawCircle(Offset(cx, baseY - unit * 17.4), unit * 0.6, stone)
      ..drawLine(
        Offset(cx, baseY - unit * 17.5),
        Offset(cx, baseY - unit * 21),
        Paint()
          ..color = stone.color
          ..strokeWidth = unit * 0.2,
      )
      ..drawPath(
        Path()
          ..moveTo(cx, baseY - unit * 21)
          ..lineTo(cx + unit * 2.2, baseY - unit * 20.3)
          ..lineTo(cx, baseY - unit * 19.6)
          ..close(),
        Paint()..color = const Color(0xFFD9642B),
      );

    final band = Paint()
      ..color = const Color(0xFF4A453D)
      ..strokeWidth = unit * 0.25;
    for (var i = 1; i <= 4; i++) {
      final y = baseY - unit * (5 + i * 2.6);
      final half = unit * (2.5 - i * 0.35);
      canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), band);
    }
  }

  @override
  bool shouldRepaint(HeroPainter oldDelegate) => oldDelegate.fadeTo != fadeTo;
}
