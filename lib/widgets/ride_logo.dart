import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Isotipo de Ride: la "R" con el pin de ubicación.
///
/// Es una aproximación en código del logo del diseño; si más adelante se
/// agrega el SVG/PNG oficial basta con reemplazar el contenido de este widget.
class RideMark extends StatelessWidget {
  const RideMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'R',
            style: TextStyle(
              fontSize: size,
              height: 1,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -size * 0.06,
            ),
          ),
          Positioned(
            right: 0,
            top: size * 0.06,
            child: Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(100),
                  topRight: Radius.circular(100),
                  bottomRight: Radius.circular(100),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Center(
                child: Container(
                  width: size * 0.16,
                  height: size * 0.16,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Isotipo + palabra "Ride", con la bajada opcional.
class RideLogo extends StatelessWidget {
  const RideLogo({
    super.key,
    this.markSize = 72,
    this.showTagline = true,
  });

  final double markSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RideMark(size: markSize),
        SizedBox(height: markSize * 0.18),
        Text(
          'Ride',
          style: TextStyle(
            fontSize: markSize * 0.72,
            height: 1,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -1,
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: markSize * 0.14),
          const Text(
            'Muévete a tu manera',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
