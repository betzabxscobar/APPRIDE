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
      decoration: BoxDecoration(gradient: ride.hero),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Imagen al 45% del alto de la vista (modo estiramiento).
          // El héroe sigue full-bleed detrás, pero la ilustración solo mide
          // 45% del viewport y sangra levemente bajo la hoja.
          final viewportHeight = constraints.maxHeight;
          final overlapTop = viewportHeight.isFinite
              ? (viewportHeight * 0.45).clamp(220.0, 380.0)
              : 280.0;

          return Stack(
            children: [
              Positioned.fill(
                child: _MobileHero(topInset: padding.top),
              ),
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewportHeight.isFinite ? viewportHeight : 0,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: overlapTop),
                      _MobileSheet(
                        minHeight: viewportHeight.isFinite
                            ? viewportHeight - overlapTop
                            : 0,
                        bottomInset: padding.bottom,
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cabecera de marca del teléfono: la misma aurora, ruta y ciudad del panel de
/// escritorio, ahora estirada para ocupar todo el espacio disponible.
///
/// En modo estiramiento la ilustración NO preserva ratio: se deforma para
/// llenar el contenedor completo y el sobrante sangra por debajo de la hoja.
class _MobileHero extends StatelessWidget {
  const _MobileHero({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final isDark = ride.isDark;

        return Stack(
          clipBehavior: Clip.none,
          children: [
              Positioned(
                left: -120,
                top: -140,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        isDark ? const Color(0x487DDBEE) : const Color(0x387DDBEE),
                        const Color(0x007DDBEE),
                      ],
                      stops: const [0, 0.68],
                    ),
                  ),
                ),
              ),
              // 45% del alto: la imagen llena el header visible (45% del
              // viewport) y queda por encima de la hoja. El bottom se calcula
              // para que la base coincida con el borde de la hoja (con 16px
              // de sangrado). Reemplaza al gráfico pintado _CityArt: así
              // desaparecen las líneas de la ruta en la vista de crear cuenta.
              Positioned(
                left: 0,
                right: 0,
                bottom: height * 0.55 - 16,
                height: height * 0.45,
                child: Image.asset(
                  'assets/images/fondoCrearCuenta.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                ),
              ),
              // Velo: más oscuro en modo nocturno para que el texto siga
              // legible sobre edificios más claros.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0x0004121B),
                        isDark ? const Color(0x9904121B) : const Color(0x6604121B),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const RideWordmark(
                      markSize: 40,
                      fontSize: 24,
                      color: Colors.white,
                    ),
                    Text(
                      'Muévete con libertad.',
                      style: AppTheme.display(
                        AppText.h2,
                        color: Colors.white,
                        letterSpacing: -0.8,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
      },
    );
  }
}

/// Hoja blanca (u oscura) donde vive el formulario.
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
    final ride = context.ride;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight > 0 ? minHeight : 0),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 32 + bottomInset),
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusSheet),
        ),
        boxShadow: [
          BoxShadow(
            color: ride.shadow,
            blurRadius: 32,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      // Centrado, no pegado arriba: en pasos cortos como la bienvenida el
      // formulario ocupa poco y dejaba media hoja en blanco debajo.
      child: Align(alignment: Alignment.center, child: child),
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

    return ColoredBox(
      color: ride.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
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
    final ride = context.ride;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final headline = (width * 0.1).clamp(45.0, 76.0);
        final isDark = ride.isDark;

        return ClipRect(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark ? ride.hero : AppColors.brandPanel,
            ),
            child: Stack(
              children: [
                // Aurora superior izquierda (`.brand-panel:before`).
                Positioned(
                  left: -170,
                  top: -160,
                  child: Container(
                    width: 430,
                    height: 430,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          isDark ? const Color(0x3A7DDBEE) : const Color(0x2A7DDBEE),
                          const Color(0x007DDBEE),
                        ],
                        stops: const [0, 0.68],
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
                  child: Image.asset(
                    'assets/images/fondoCrearCuenta.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(32, width * 0.09),
                    vertical: 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RideWordmark(color: Colors.white),
                      SizedBox(height: height * 0.12),
                      _Headline(size: headline, isDark: isDark),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: 450,
                        child: Text(
                          'Una forma más segura, transparente y humana de '
                          'llegar a donde quieres.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.65,
                            color: isDark ? const Color(0xFFB4C8D3) : AppColors.navySoft,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _TrustRow(isDark: isDark),
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
  const _Headline({required this.size, this.isDark = false});

  final double size;
  final bool isDark;

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
            style: style.copyWith(
              color: isDark ? const Color(0xFF8ADFF0) : AppColors.sky,
            ),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// Sellos inferiores (`.trust`): la primera letra va en verde menta.
class _TrustRow extends StatelessWidget {
  const _TrustRow({this.isDark = false});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 25,
      runSpacing: 8,
      children: [
        _TrustBadge(symbol: '◈', label: ' Viajes protegidos', isDark: isDark),
        _TrustBadge(symbol: '◉', label: ' Precio transparente', isDark: isDark),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.symbol, required this.label, this.isDark = false});

  final String symbol;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: symbol,
            style: TextStyle(color: isDark ? const Color(0xFF6ED9C8) : AppColors.mint),
          ),
          TextSpan(text: label),
        ],
      ),
      style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF91AEBE) : AppColors.navyFaint),
    );
  }
}

