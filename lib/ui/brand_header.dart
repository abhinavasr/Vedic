import 'package:flutter/material.dart';

import 'theme.dart';

/// Logo, name and settings button at the top of the main screens.
class SadhanaHeader extends StatelessWidget {
  const SadhanaHeader({
    super.key,
    required this.onOpenSettings,
    this.onDark = true,
  });

  final VoidCallback onOpenSettings;

  /// Whether it sits on a dark image (white type) or a light one.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? Colors.white : SadhanaColors.ink;
    final soft = onDark
        ? Colors.white.withValues(alpha: 0.85)
        : SadhanaColors.inkSoft;
    final shadows = onDark
        ? const [Shadow(color: Color(0x66000000), blurRadius: 12)]
        : const <Shadow>[];

    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFBF1E1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset(
              'assets/images/sadhana_emblem.png',
              width: 46,
              height: 46,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            // Without this the column fills the hero's height and drags the
            // logo and settings button to the middle of it.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sadhana',
                style: serif(size: 30, color: ink).copyWith(shadows: shadows),
              ),
              Text(
                'Scripture  ·  Calendar  ·  Self',
                style: TextStyle(fontSize: 14, color: soft, shadows: shadows),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: Icon(
            Icons.settings_outlined,
            color: onDark ? Colors.white : SadhanaColors.gold,
            size: 28,
          ),
        ),
      ],
    );
  }
}
