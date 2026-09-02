import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../widgets/ride_logo.dart';

/// Pantalla de bienvenida con hero visual: imagen de fondo, ilustraciones
/// superpuestas y opciones para elegir entre pasajero o conductor.
class WelcomeHomeScreen extends StatelessWidget {
  const WelcomeHomeScreen({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final isDark = ride.isDark;
    final padding = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: ride.background,
      // Tarjeta anclada reciclada de 'Crear cuenta' (_MobileSheet / AuthCard):
      // hero 60% + sheet 40% con mismo radius/sombra.
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ride.hero),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            final heroHeight = viewportHeight.isFinite
                ? (viewportHeight * 0.60).clamp(340.0, 560.0)
                : 420.0;
            final overlapTop = heroHeight;

            final isTall = viewportHeight > 850;
            final isVeryTall = viewportHeight > 1000;

            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: heroHeight,
                  child: _HeroVisual(isDark: isDark),
                ),
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: viewportHeight.isFinite ? viewportHeight : 0,
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: overlapTop),
                        _WelcomeSheet(
                          minHeight: viewportHeight.isFinite
                              ? viewportHeight - overlapTop
                              : 0,
                          bottomInset: padding.bottom,
                          onContinue: onContinue,
                          isTall: isTall,
                          isVeryTall: isVeryTall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta anclada reutilizada de `auth_shell.dart:_MobileSheet`.
///
/// Mismo `ride.surface + radiusSheet 28 + shadow + padding 24/28` para que
/// 'Bienvenido a Ride' se vea idéntica a 'Crear cuenta', pero responsiva:
/// en pantallas grandes distribuye el alto y muestra beneficios/legal.
class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({
    required this.minHeight,
    required this.bottomInset,
    required this.onContinue,
    this.isTall = false,
    this.isVeryTall = false,
  });

  final double minHeight;
  final double bottomInset;
  final VoidCallback onContinue;
  final bool isTall;
  final bool isVeryTall;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final isDark = ride.isDark;

    // Tipografía y botón crecen levemente en pantallas grandes
    final titleSize = isVeryTall ? 30.0 : (isTall ? 28.0 : 26.0);
    final buttonHeight = isVeryTall ? 56.0 : 52.0;
    final verticalPadding = isTall ? 32.0 : 28.0;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight > 0 ? minHeight : 0),
      padding: EdgeInsets.fromLTRB(24, verticalPadding, 24, 32 + bottomInset + (isTall ? 12 : 0)),
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
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle sutil como en BottomSheet
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ride.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: isTall ? 24 : 20),
              Text(
                'Bienvenido a Ride',
                style: AppTheme.display(
                  titleSize,
                  color: ride.ink,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Elige cómo quieres usar Ride',
                style: AppTheme.display(
                  15,
                  color: ride.inkMuted,
                ),
                textAlign: TextAlign.center,
              ),
              // Espaciador proporcional que crece en pantallas grandes
              SizedBox(height: isTall ? 24 : 16),
              if (isTall) ...[
                Row(
                  children: [
                    for (final b in const [
                      _BenefitData(icon: Icons.shield_outlined, label: 'Seguro'),
                      _BenefitData(icon: Icons.eco_outlined, label: 'Sostenible'),
                      _BenefitData(icon: Icons.favorite_outline, label: 'Confiable'),
                    ])
                      Expanded(child: _BenefitTile(data: b)),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(color: ride.border, height: 1, thickness: 1),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: buttonHeight,
                child: FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: ride.accent,
                    foregroundColor: isDark ? const Color(0xFF04121C) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Continuar',
                    style: AppTheme.display(
                      17,
                      color: isDark ? const Color(0xFF04121C) : Colors.white,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (isTall) ...[
                const SizedBox(height: 16),
                _LegalNote(isDark: isDark),
                SizedBox(height: isVeryTall ? 16 : 8),
              ] else
                const SizedBox(height: 4),
              // Padding extra proporcional en pantallas muy grandes para
              // no dejar hueco centrado sin usar Spacer (evita Flex error)
              SizedBox(height: isVeryTall ? 24 : (isTall ? 12 : 0)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitData {
  const _BenefitData({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.data});
  final _BenefitData data;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ride.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ride.border, width: 1),
          ),
          child: Icon(data.icon, size: 22, color: ride.accent),
        ),
        const SizedBox(height: 8),
        Text(
          data.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ride.inkMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LegalNote extends StatelessWidget {
  const _LegalNote({this.isDark = false});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final link = TextStyle(
      color: ride.accent,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: ride.accent,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Al continuar aceptas nuestros '),
          TextSpan(text: 'Términos', style: link),
          const TextSpan(text: ' y la '),
          TextSpan(text: 'Política de privacidad', style: link),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: AppText.micro,
        height: 1.6,
        color: ride.inkFaint,
      ),
    );
  }
}

/// Widget hero con imagen de fondo, logo arriba, y personajes superpuestos
/// con animación de entrada.
class _HeroVisual extends StatefulWidget {
  const _HeroVisual({this.isDark = false});

  final bool isDark;

  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual>
    with TickerProviderStateMixin {
  late final AnimationController _girlCtrl;
  late final AnimationController _boyCtrl;
  late final AnimationController _carCtrl;

  @override
  void initState() {
    super.initState();

    _girlCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _boyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _carCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Iniciar animaciones con efecto cascada
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _girlCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _boyCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _carCtrl.forward();
    });
  }

  @override
  void dispose() {
    _girlCtrl.dispose();
    _boyCtrl.dispose();
    _carCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return ClipRRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Imagen de fondo — sin filtro, asset distinto por tema ──
          Image.asset(
            isDark ? 'assets/images/fondoInicioNocturno.jpeg' : 'assets/images/fondoInicio.jpeg',
            fit: BoxFit.cover,
          ),

          // ── Degradado sutil en la parte inferior ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    isDark ? const Color(0xFF0E2432) : AppColors.background,
                  ],
                ),
              ),
            ),
          ),

          // ── Logo arriba al centro ──
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: RideMark(size: 90),
            ),
          ),

          // ── Título "RIDE" ──
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'RIDE',
                style: AppTheme.display(
                  42,
                  color: isDark ? Colors.white : AppColors.ink,
                  letterSpacing: 2,
                  height: 1,
                ),
              ),
            ),
          ),

          // ── Subtítulo ──
          Positioned(
            top: 170,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Muévete a tu manera',
                style: AppTheme.display(
                  16,
                  color: isDark ? const Color(0xFFB4C8D3) : AppColors.inkMuted,
                  letterSpacing: 0,
                  height: 1.3,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // ── Chica animada (entra desde la izquierda) ──
          Positioned(
            left: 10,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _girlCtrl,
              builder: (context, child) {
                final value = Curves.easeOut.transform(_girlCtrl.value);
                return Transform.translate(
                  offset: Offset(-200 * (1 - value), 0),
                  child: child,
                );
              },
              child: const Image(
                image: AssetImage('assets/images/ChicaDibujo.png'),
                width: 130,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ── Carro animado (entra desde la derecha) ──
          Positioned(
            left: 0,
            right: 40,
            bottom: -60,
            child: Align(
              alignment: Alignment.bottomRight,
              child: AnimatedBuilder(
                animation: _carCtrl,
                builder: (context, child) {
                  final value = Curves.easeOut.transform(_carCtrl.value);
                  return Transform.translate(
                    offset: Offset(300 * (1 - value), 0),
                    child: child,
                  );
                },
                child: const Image(
                  image: AssetImage('assets/images/carroDibujo.png'),
                  width: 220,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // ── Chico animado (entra desde la derecha) ──
          Positioned(
            right: 10,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _boyCtrl,
              builder: (context, child) {
                final value = Curves.easeOut.transform(_boyCtrl.value);
                return Transform.translate(
                  offset: Offset(200 * (1 - value), 0),
                  child: child,
                );
              },
              child: const Image(
                image: AssetImage('assets/images/ChicoDibujo.png'),
                width: 130,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
