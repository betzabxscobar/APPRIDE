import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';

/// Tarjeta blanca con sombra suave, el contenedor base del diseño.
class RideCard extends StatelessWidget {
  const RideCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusLarge);

    return Material(
      color: color,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}
