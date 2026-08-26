import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import 'ride_logo.dart';

/// Estructura de las pantallas de autenticación, igual que `.auth-page` en
/// WEB-RIDE: panel de marca oscuro a la izquierda y panel del formulario a la
/// derecha. Bajo 850 px de ancho el panel de marca se oculta y solo queda la
/// marca pequeña arriba a la izquierda, tal como hace el `@media` de la web.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppTheme.wideBreakpoint;

          if (!wide) return _FormPanel(compact: true, child: child);

          return Row(
            children: [
              // minmax(420px,1.05fr) minmax(480px,.95fr)
              Expanded(flex: 105, child: const BrandPanel()),
              Expanded(flex: 95, child: _FormPanel(child: child)),
            ],
          );
        },
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.formPanel),
      child: SafeArea(
        child: compact
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RideWordmark(markSize: 35, fontSize: 22),
                    const SizedBox(height: 38),
                    child,
                  ],
                ),
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 40,
                  ),
                  child: Center(child: child),
                ),
              ),
      ),
    );
  }
}

/// Columna oscura de la izquierda (`.brand-panel`).
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final headline = (width * 0.1).clamp(45.0, 76.0);

        return ClipRect(
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppColors.brandPanel),
            child: Stack(
              children: [
                // Aurora superior izquierda (`.brand-panel:before`).
                Positioned(
                  left: -170,
                  top: -160,
                  child: Container(
                    width: 430,
                    height: 430,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x2A7DDBEE), Color(0x007DDBEE)],
                        stops: [0, 0.68],
                      ),
                    ),
                  ),
                ),
                // Anillo superior derecho (`.brand-panel:after`).
                Positioned(
                  right: -220,
                  top: -200,
                  child: Container(
                    width: 520,
                    height: 520,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF97E2F1).withValues(alpha: 0.05),
                        width: 90,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: height * 0.43,
                  child: const _CityArt(),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(32, width * 0.09),
                    vertical: 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RideWordmark(color: Colors.white),
                      SizedBox(height: height * 0.12),
                      _Headline(size: headline),
                      const SizedBox(height: 25),
                      const SizedBox(
                        width: 450,
                        child: Text(
                          'Una forma más segura, transparente y humana de '
                          'llegar a donde quieres.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.65,
                            color: AppColors.navySoft,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const _TrustRow(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Muévete con **libertad.**" (`.brand-copy h1`).
class _Headline extends StatelessWidget {
  const _Headline({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.display(
      size,
      color: Colors.white,
      letterSpacing: -3,
      height: 1.02,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Muévete con\n'),
          TextSpan(
            text: 'libertad.',
            style: style.copyWith(color: AppColors.sky),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// Sellos inferiores (`.trust`): la primera letra va en verde menta.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 25,
      runSpacing: 8,
      children: [
        _TrustBadge(symbol: '◈', label: ' Viajes protegidos'),
        _TrustBadge(symbol: '◉', label: ' Precio transparente'),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.symbol, required this.label});

  final String symbol;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: symbol,
            style: const TextStyle(color: AppColors.mint),
          ),
          TextSpan(text: label),
        ],
      ),
      style: const TextStyle(fontSize: 11, color: AppColors.navyFaint),
    );
  }
}

/// Ilustración de la ciudad (`.city-art`): luna, ruta, auto y edificios.
class _CityArt extends StatelessWidget {
  const _CityArt();

  static const List<double> _buildingHeights = [
    0.42,
    0.72,
    0.53,
    0.88,
    0.61,
    0.76,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x143BA4CB)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: width * 0.15,
                top: height * 0.06,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.24, -0.24),
                      colors: [Color(0x2EB5EDF7), Color(0x0969D2F0)],
                      stops: [0, 0.66],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: width * 0.05,
                right: width * 0.05,
                bottom: 0,
                height: height * 0.7,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, fraction) in _buildingHeights.indexed) ...[
                      Expanded(
                        child: Container(
                          height: height * 0.7 * fraction,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF123B50), Color(0xFF0C2D40)],
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      if (index != _buildingHeights.length - 1)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: width * 0.14,
                top: height * 0.24,
                width: width * 0.58,
                height: height * 0.42,
                child: const _Route(),
              ),
              Positioned(
                left: width * 0.58,
                top: height * 0.48,
                child: Transform.rotate(
                  angle: -7 * math.pi / 180,
                  child: const Text(
                    '▰',
                    style: TextStyle(fontSize: 42, color: Color(0xFFA5E8F4)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Trazo de la ruta con sus tres paradas (`.route`).
class _Route extends StatelessWidget {
  const _Route();

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(-18 * math.pi / 180),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
              Positioned(left: -5, bottom: -8, child: const _RouteStop()),
              Positioned(left: width * 0.5, bottom: -8, child: const _RouteStop()),
              Positioned(right: -8, top: -6, child: const _RouteStop()),
            ],
          );
        },
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  static const double _radius = 70;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(_radius, math.min(size.width, size.height));
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(
        Offset(size.width, size.height - radius),
        radius: const Radius.circular(_radius),
        clockwise: false,
      )
      ..lineTo(size.width, 0);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF5ECFEE).withValues(alpha: 0.36)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF69CDE9);

    canvas
      ..drawPath(path, glow)
      ..drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RouteStop extends StatelessWidget {
  const _RouteStop();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0C2C43),
        border: Border.all(color: const Color(0xFF8ADFF0), width: 3),
      ),
    );
  }
}
