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
            child: _HeroVisual(),
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

/// Widget hero con imagen de fondo, logo arriba, y personajes superpuestos.
class _HeroVisual extends StatelessWidget {
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
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: RideMark(size: 90),
            ),
          ),

          // ── Chica a la izquierda ──
          Positioned(
            left: 10,
            bottom: 30,
            child: Image.asset(
              'assets/images/ChicaDibujo.png',
              width: 130,
              fit: BoxFit.contain,
            ),
          ),

          // ── Carro al centro ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: Image.asset(
                'assets/images/carroDibujo.png',
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ── Chico a la derecha ──
          Positioned(
            right: 10,
            bottom: 30,
            child: Image.asset(
              'assets/images/ChicoDibujo.png',
              width: 130,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
