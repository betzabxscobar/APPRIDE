import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../widgets/auth_widgets.dart';

/// Bienvenida equivalente a `.welcome-box` de WEB-RIDE.
class WelcomeBox extends StatelessWidget {
  const WelcomeBox({super.key, required this.onRegister, required this.onLogin});

  final VoidCallback onRegister;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final headingSize = width < AppTheme.wideBreakpoint
        ? (width * 0.08).clamp(28.0, 38.0)
        : 39.0;

    return AuthCard(
      children: [
        const _AuthIcon(),
        const AuthEyebrow('BIENVENIDO A RIDE'),
        AuthHeading(
          'Tu próximo viaje\nempieza aquí.',
          size: headingSize,
        ),
        const AuthLead(
          'Crea una cuenta o inicia sesión para continuar.',
          bottomSpacing: 22,
        ),
        PrimaryAction(label: 'Crear cuenta', onPressed: onRegister),
        const SizedBox(height: 10),
        SecondaryAction(label: 'Ya tengo una cuenta', onPressed: onLogin),
        const _AuthAssurance(),
      ],
    );
  }
}

class _AuthIcon extends StatelessWidget {
  const _AuthIcon();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 46,
        height: 46,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ride.accentSoft, ride.successSoft],
          ),
          border: Border.all(color: ride.accent.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: ride.accent.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Icon(Icons.shield_outlined, color: ride.accent, size: 21),
      ),
    );
  }
}

class _AuthAssurance extends StatelessWidget {
  const _AuthAssurance();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ride.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 15, color: ride.success),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Tus datos viajan protegidos',
              textAlign: TextAlign.center,
              style: TextStyle(color: ride.inkMuted, fontSize: AppText.micro),
            ),
          ),
        ],
      ),
    );
  }
}
