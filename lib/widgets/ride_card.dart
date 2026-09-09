import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Tarjeta base del diseño.
///
/// En claro se apoya en una sombra suave y un borde muy tenue; en oscuro la
/// sombra no se ve, así que el relieve lo da el borde. Antes era solo un borde
/// gris de 1 px, que en el teléfono se lee como una tabla de página web.
class RideCard extends StatelessWidget {
  const RideCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final radius = BorderRadius.circular(AppTheme.radiusLarge);
    final background = color ?? ride.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background,
            Color.lerp(background, ride.accentSoft, ride.isDark ? 0.10 : 0.035)!,
          ],
        ),
        boxShadow: ride.isDark
            ? null
            : [
                BoxShadow(
                  color: ride.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: borderColor ?? ride.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
