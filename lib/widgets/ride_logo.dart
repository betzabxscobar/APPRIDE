import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Isotipo de Ride construido con el icono Material de transporte.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 52});

  /// Alto del isotipo.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.local_taxi_rounded,
      size: size,
      color: context.ride.accent,
    );
  }
}

/// Isotipo + la palabra "Ride" (`.wordmark`, `.mobile-brand`, `.mini-brand`).
class RideWordmark extends StatelessWidget {
  const RideWordmark({
    super.key,
    this.markSize = 52,
    this.fontSize = 28,
    this.color,
  });

  final double markSize;
  final double fontSize;

  /// Color de la palabra "Ride". Si no se indica, sigue el tema: sobre el
  /// héroe de marca se pasa blanco a mano.
  final Color? color;

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
            color: color ?? context.ride.ink,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}
