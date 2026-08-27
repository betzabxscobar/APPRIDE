import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Isotipo de Ride: el hexágono con la "R".
///
/// Es la traducción del `.logo` de WEB-RIDE (`clip-path` hexagonal, degradado
/// celeste y sombra suave), para que la marca sea la misma en web y en la app.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 52});

  /// Alto del isotipo. El ancho sale de la proporción original (46 × 52).
  final double size;

  @override
  Widget build(BuildContext context) {
    final width = size * 46 / 52;

    return SizedBox(
      width: width,
      height: size,
      child: ClipPath(
        clipper: const _HexagonClipper(),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.logo),
          child: Center(
            child: Text(
              'R',
              style: AppTheme.display(
                size * 0.54,
                color: const Color(0xFF062033),
                letterSpacing: 0,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `polygon(17% 0,83% 0,100% 18%,100% 72%,56% 100%,43% 100%,0 72%,0 18%)`
class _HexagonClipper extends CustomClipper<Path> {
  const _HexagonClipper();

  static const List<Offset> _points = [
    Offset(0.17, 0),
    Offset(0.83, 0),
    Offset(1, 0.18),
    Offset(1, 0.72),
    Offset(0.56, 1),
    Offset(0.43, 1),
    Offset(0, 0.72),
    Offset(0, 0.18),
  ];

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final (index, point) in _points.indexed) {
      final offset = Offset(point.dx * size.width, point.dy * size.height);
      index == 0 ? path.moveTo(offset.dx, offset.dy) : path.lineTo(offset.dx, offset.dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
