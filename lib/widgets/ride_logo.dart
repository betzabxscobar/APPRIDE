import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';

/// Isotipo de Ride: imagen del logo.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 52});

  /// Alto del isotipo.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/fonts/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Isotipo + la palabra "Ride" (`.wordmark`, `.mobile-brand`, `.mini-brand`).
class RideWordmark extends StatelessWidget {
  RideWordmark({
    super.key,
    this.markSize = 52,
    this.fontSize = 28,
    this.color = AppColors.ink,
  });

  final double markSize;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RideMark(size: markSize),
        const SizedBox(width: 12),
        Text(
          'Ride',
          style: AppTheme.display(
            fontSize,
            color: color,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}
