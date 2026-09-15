import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dawn over mountain ridges with a temple silhouette, fading into the page
/// background. Painted rather than a photo so it costs no app size.
///
/// [light] paints a pale morning version for screens with dark type on top.
class HeroPainter extends CustomPainter {
  const HeroPainter({required this.fadeTo, this.light = false});

  final Color fadeTo;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: light
              ? const [
                  Color(0xFFF7EBDD),
                  Color(0xFFF6DDC0),
                  Color(0xFFF2CFA2),
                  Color(0xFFF6E3C6),
                ]
              : const [
                  Color(0xFF55667A),
                  Color(0xFFA2958C),
                  Color(0xFFE8B982),
                  Color(0xFFF3D9B0),
                ],
          stops: const [0, 0.36, 0.58, 0.76],
        ).createShader(rect),
    );

    final sun = Offset(size.width * 0.7, size.height * 0.56);
    final glow = Rect.fromCircle(center: sun, radius: size.width * 0.36);
    canvas
      ..drawCircle(
        sun,
        glow.width / 2,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xDDFFE7B0), Color(0x00FFE7B0)],
          ).createShader(glow),
      )
      ..drawCircle(sun, 10, Paint()..color = const Color(0xFFFFF6DE));

    _ridge(
      canvas,
      size,
      base: 0.6,
      amp: 0.14,
      seed: 1,
      color: light ? const Color(0x55B79B86) : const Color(0x996F7A86),
    );
    _ridge(
      canvas,
      size,
      base: 0.68,
      amp: 0.1,
      seed: 2,
      color: light ? const Color(0x88A0826C) : const Color(0xCC4B5563),
    );
    _temple(canvas, size);
    _ridge(
      canvas,
      size,
      base: 0.8,
      amp: 0.06,
      seed: 3,
      color: light ? const Color(0xAA7F7457) : const Color(0xFF2F3A33),
    );

    final fade = Rect.fromLTWH(
      0,
      size.height * 0.72,
      size.width,
      size.height * 0.28,
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

  /// A small shikhara temple on the right-hand ridge, below the header.
  void _temple(Canvas canvas, Size size) {
    final unit = size.width * 0.0105;
    final cx = size.width * 0.88;
    final baseY = size.height * 0.72;
    final stone = Paint()
      ..color = light ? const Color(0xFF7A6553) : const Color(0xFF34302B);

    canvas
      ..drawRect(
        Rect.fromLTRB(
          cx - unit * 8,
          baseY - unit * 1.2,
          cx + unit * 6,
          baseY + unit * 6,
        ),
        stone,
      )
      ..drawRect(
        Rect.fromLTRB(cx - unit * 7, baseY - unit * 4, cx - unit * 1.5, baseY),
        stone,
      )
      ..drawPath(
        Path()
          ..moveTo(cx - unit * 7.5, baseY - unit * 4)
          ..lineTo(cx - unit * 4.25, baseY - unit * 7)
          ..lineTo(cx - unit, baseY - unit * 4)
          ..close(),
        stone,
      )
      ..drawPath(
        Path()
          ..moveTo(cx - unit * 2.6, baseY)
          ..lineTo(cx - unit * 2.6, baseY - unit * 5)
          ..quadraticBezierTo(
            cx - unit * 2.5,
            baseY - unit * 13,
            cx,
            baseY - unit * 17,
          )
          ..quadraticBezierTo(
            cx + unit * 2.5,
            baseY - unit * 13,
            cx + unit * 2.6,
            baseY - unit * 5,
          )
          ..lineTo(cx + unit * 2.6, baseY)
          ..close(),
        stone,
      )
      ..drawCircle(Offset(cx, baseY - unit * 17.4), unit * 0.7, stone)
      ..drawLine(
        Offset(cx, baseY - unit * 17.5),
        Offset(cx, baseY - unit * 22),
        Paint()
          ..color = stone.color
          ..strokeWidth = math.max(1, unit * 0.25),
      )
      ..drawPath(
        Path()
          ..moveTo(cx, baseY - unit * 22)
          ..lineTo(cx + unit * 3, baseY - unit * 21)
          ..lineTo(cx, baseY - unit * 20)
          ..close(),
        Paint()..color = const Color(0xFFD9642B),
      );

    final band = Paint()
      ..color = light ? const Color(0xFF8E7864) : const Color(0xFF4A453D)
      ..strokeWidth = math.max(1, unit * 0.3);
    for (var i = 1; i <= 4; i++) {
      final y = baseY - unit * (5 + i * 2.6);
      final half = unit * (2.6 - i * 0.35);
      canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), band);
    }
  }

  @override
  bool shouldRepaint(HeroPainter oldDelegate) =>
      oldDelegate.fadeTo != fadeTo || oldDelegate.light != light;
}
