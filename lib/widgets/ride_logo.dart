import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Isotipo de Ride.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 52});

  /// Alto del isotipo.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // El PNG tiene margen transparente arriba; se compensa para alinear la
      // parte visible del símbolo con la palabra Ride.
      offset: const Offset(0, -12),
      child: Image.asset(
        'assets/images/LopoTipo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Isotipo + la palabra "Ride" (`.wordmark`, `.mobile-brand`, `.mini-brand`).
class RideWordmark extends StatelessWidget {
  const RideWordmark({
    super.key,
    this.markSize = 64,
    this.fontSize = 28,
    this.color,
    this.subtitle,
    this.subtitleColor,
    this.subtitleFontSize = 11,
  });

  final double markSize;
  final double fontSize;

  /// Color de la palabra "Ride". Si no se indica, sigue el tema: sobre el
  /// héroe de marca se pasa blanco a mano.
  final Color? color;
  final String? subtitle;
  final Color? subtitleColor;
  final double subtitleFontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideMark(size: markSize),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ride',
              style: AppTheme.display(
                fontSize,
                color: color ?? context.ride.ink,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: subtitleFontSize,
                  color: subtitleColor ?? color ?? context.ride.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
