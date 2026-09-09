import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Isotipo de Ride.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 52});

  /// Ancho del isotipo, igual que en el `wordmark-logo` de WEB-RIDE.
  final double size;

  @override
  Widget build(BuildContext context) {
    // El archivo tiene proporción 4:3. Reservar esa misma caja evita que el
    // logo se reduzca dentro de un cuadrado y que haya que moverlo a mano.
    return SizedBox(
      width: size,
      height: size * 0.75,
      child: Image.asset(
        'assets/images/LogoTipo.png',
        width: size,
        height: size * 0.75,
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
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
      ),
    );
  }
}
