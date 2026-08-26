import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
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
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Hero visual: 60% del alto ──
          SizedBox(
            width: size.width,
            height: size.height * 0.60,
            child: const _HeroVisual(),
          ),

          // ── Contenido inferior ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Título
                  Text(
                    'Bienvenido a Ride',
                    style: AppTheme.display(
                      26,
                      color: AppColors.ink,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Elige cómo quieres usar Ride',
                    style: AppTheme.display(
                      15,
                      color: AppColors.inkMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 2),

                  // Botón continuar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Continuar',
                        style: AppTheme.display(
                          17,
                          color: Colors.white,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget hero con imagen de fondo, logo arriba, y personajes superpuestos
/// con animación de entrada.
class _HeroVisual extends StatefulWidget {
  const _HeroVisual();

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
    return ClipRRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Imagen de fondo ──
          Image.asset(
            'assets/images/fondoInicio.jpeg',
            fit: BoxFit.cover,
          ),

          // ── Degradado sutil en la parte inferior ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 80,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.background],
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
                  color: AppColors.ink,
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
                  color: AppColors.inkMuted,
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
