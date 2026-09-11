import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import 'ride_logo.dart';

/// Estructura de las pantallas de autenticación.
///
/// Son dos diseños distintos, no uno que se encoge:
///
/// * **Ancho (≥850 px)**, escritorio y tablet: el `.auth-page` de WEB-RIDE, con
///   el panel de marca oscuro a la izquierda y el formulario a la derecha.
/// * **Angosto**, el teléfono: la marca ocupa el fondo entero y el formulario
///   sube en una hoja redondeada, como en cualquier app móvil.
///
/// Antes el móvil era el caso degradado del diseño web: se ocultaba el panel de
/// marca y quedaba una tarjeta blanca sobre fondo casi blanco, sin identidad y
/// con tipografías pensadas para leerse en un monitor. Ahora el teléfono tiene
/// su propia composición y es la marca la que da el fondo.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppTheme.wideBreakpoint;

          if (!wide) return _MobileAuthLayout(child: child);

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

/// Composición de teléfono: héroe de marca arriba, hoja con el formulario
/// abajo.
///
/// La hoja se apoya sobre el héroe y lo tapa al desplazarse, así que un
/// formulario largo como el registro se come el héroe en vez de pelear con él
/// por el espacio.
class _MobileAuthLayout extends StatelessWidget {
  const _MobileAuthLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final padding = MediaQuery.paddingOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ride.background,
        gradient: ride.isDark
            ? ride.hero
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF9FCFD), Color(0xFFEEF6F8)],
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: padding.top + 72,
                  child: _MobileHero(topInset: padding.top),
                ),
                _MobileSheet(
                  minHeight: constraints.maxHeight - padding.top - 72,
                  bottomInset: padding.bottom,
                  child: child,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Marca compacta que WEB-RIDE muestra sobre la tarjeta en pantallas angostas.
class _MobileHero extends StatelessWidget {
  const _MobileHero({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RideWordmark(
          markSize: 42,
          fontSize: 22,
          color: ride.ink,
        ),
      ),
    );
  }
}

/// Espacio desplazable donde vive la tarjeta del formulario en móvil.
class _MobileSheet extends StatelessWidget {
  const _MobileSheet({
    required this.child,
    required this.minHeight,
    required this.bottomInset,
  });

  final Widget child;
  final double minHeight;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 18.0 : 24.0;
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight > 0 ? minHeight : 0),
          padding: EdgeInsets.fromLTRB(
            horizontal,
            8,
            horizontal,
            18 + bottomInset,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: _AuthContent(child: child),
          ),
        );
      },
    );
  }
}

/// Columna del formulario en escritorio (`.form-panel`).
class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ride.isDark
            ? ride.hero
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF9FCFD), Color(0xFFEEF6F8)],
              ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 540 ? 28 : 48,
                vertical: constraints.maxHeight < 650 ? 24 : 40,
              ),
              child: Center(child: _AuthContent(child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthContent extends StatelessWidget {
  const _AuthContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AuthSurface(child: child),
        const SizedBox(height: 16),
        const _LegalFooter(),
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _TermsDialog(),
          ),
          child: const Text('Términos y condiciones'),
        ),
        Text(
          '© 2026 Ride. Todos los derechos reservados.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ride.inkMuted, fontSize: AppText.micro),
        ),
      ],
    );
  }
}

class _TermsDialog extends StatelessWidget {
  const _TermsDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Términos y condiciones'),
      content: const SingleChildScrollView(
        child: Text(
          'Al crear una cuenta o utilizar Ride, aceptas proporcionar información veraz y usar la plataforma de forma segura, respetuosa y conforme a la ley.\n\n'
          'Los viajes, pagos, rutas y comunicaciones se gestionan según la disponibilidad del servicio. Cada persona usuaria es responsable de proteger sus credenciales y revisar la información de cada viaje.\n\n'
          'Ride puede actualizar estos términos para mejorar el servicio o cumplir obligaciones legales. Te avisaremos cuando un cambio relevante requiera tu atención.',
          style: TextStyle(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

class _AuthSurface extends StatelessWidget {
  const _AuthSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final compact = MediaQuery.sizeOf(context).width <= 430;

    return Container(
      width: 500,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 38,
        vertical: compact ? 23 : 34,
      ),
      decoration: BoxDecoration(
        color: ride.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        border: Border.all(color: ride.border.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E3649).withValues(alpha: 0.12),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Columna oscura de la izquierda (`.brand-panel`).
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compactHeight = height < 650;
        final headline = math.min(
          (width * 0.1).clamp(40.0, 76.0),
          (height * 0.085).clamp(40.0, 68.0),
        );

        return ClipRect(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: ride.hero),
            child: Stack(
              children: [
                if (ride.isDark)
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/fondoInicioOscuro-v2.webp',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                // Aurora superior izquierda (`.brand-panel:before`).
                if (!ride.isDark)
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
                if (!ride.isDark)
                  Positioned(
                    right: -220,
                    top: -200,
                    child: Container(
                      width: 520,
                      height: 520,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFF97E2F1,
                          ).withValues(alpha: 0.05),
                          width: 90,
                        ),
                      ),
                    ),
                  ),
                if (!ride.isDark)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: height * 0.43,
                    child: const _CityArt(),
                  )
                else
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x22061F31), Color(0xA6030F19)],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(32, width * 0.09),
                    vertical: compactHeight ? 28 : 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RideWordmark(color: Color(0xFFD8F3FF)),
                      SizedBox(height: (height * 0.1).clamp(32.0, 94.0)),
                      _Headline(size: headline),
                      SizedBox(height: compactHeight ? 14 : 25),
                      SizedBox(
                        width: math.min(450, width * 0.82),
                        child: const Text(
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
      color: const Color(0xFFD8F3FF),
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
        _TrustBadge(icon: _SteeringWheelIcon(), label: 'Viajes protegidos'),
        _TrustBadge(
          icon: Icon(Icons.contactless_outlined),
          label: 'Precio transparente',
        ),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(
          data: const IconThemeData(color: AppColors.mint, size: 14),
          child: SizedBox.square(dimension: 14, child: icon),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.navyFaint),
        ),
      ],
    );
  }
}

class _SteeringWheelIcon extends StatelessWidget {
  const _SteeringWheelIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SteeringWheelPainter(IconTheme.of(context).color!),
    );
  }
}

class _SteeringWheelPainter extends CustomPainter {
  const _SteeringWheelPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * .2, paint);
    for (final angle in const [-1.5708, .5236, 2.618]) {
      canvas.drawLine(
        center + Offset.fromDirection(angle, radius * .2),
        center + Offset.fromDirection(angle, radius * .78),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SteeringWheelPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Ilustración de la ciudad (`.city-art`): ruta, auto y edificios.
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
                left: width * 0.05,
                right: width * 0.05,
                bottom: 0,
                height: height * 0.7,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, fraction)
                        in _buildingHeights.indexed) ...[
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
              Positioned(
                left: width * 0.5,
                bottom: -8,
                child: const _RouteStop(),
              ),
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
