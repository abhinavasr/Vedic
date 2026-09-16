import 'package:flutter/material.dart';

import '../theme.dart';

/// The photograph behind the top of a screen.
///
/// It fades into the page colour at its foot, so the content below starts on
/// the background rather than against a hard edge.
class HeroBackground extends StatelessWidget {
  const HeroBackground({
    super.key,
    this.fadeTo = SadhanaColors.background,
    this.child,
  });

  /// The colour the picture dissolves into at the bottom.
  final Color fadeTo;

  final Widget? child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // Behind the picture, so a slow decode shows the page's own colour
    // rather than a white flash.
    decoration: BoxDecoration(color: fadeTo),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/hero.jpg', fit: BoxFit.cover),
        // Text sits on the sky, which is bright: a wash keeps it readable
        // without hiding the picture.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0x40000000),
                const Color(0x1A000000),
                fadeTo.withValues(alpha: 0.65),
                fadeTo,
              ],
              stops: const [0, 0.45, 0.85, 1],
            ),
          ),
        ),
        ?child,
      ],
    ),
  );
}
