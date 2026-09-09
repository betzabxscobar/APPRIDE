import 'package:flutter/material.dart';

import '../core/ride_colors.dart';

/// Fondo compartido de las pantallas de contenido, inspirado en la malla
/// luminosa de WEB-RIDE. Las formas son decorativas y no capturan gestos.
class RidePageBackground extends StatelessWidget {
  const RidePageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final opacity = ride.isDark ? 0.16 : 0.48;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: ride.background),
        IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              children: [
                Positioned(
                  top: -90,
                  right: -55,
                  child: _Glow(
                    size: 230,
                    color: ride.accent.withValues(alpha: opacity),
                  ),
                ),
                Positioned(
                  bottom: -110,
                  left: -70,
                  child: _Glow(
                    size: 270,
                    color: ride.success.withValues(alpha: opacity * .72),
                  ),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}
