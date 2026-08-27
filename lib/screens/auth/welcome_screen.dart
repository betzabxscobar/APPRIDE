import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../widgets/auth_widgets.dart';

/// Bienvenida: la puerta de entrada al registro y al inicio de sesión.
class WelcomeBox extends StatelessWidget {
  const WelcomeBox({
    super.key,
    required this.onRegister,
    required this.onLogin,
  });

  final VoidCallback onRegister;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      children: [
        const AuthEyebrow('BIENVENIDO A RIDE'),
        const AuthHeading('Tu próximo viaje\nempieza aquí.'),
        const AuthLead(
          'Crea una cuenta o inicia sesión para continuar.',
          bottomSpacing: 30,
        ),
        PrimaryAction(label: 'Crear cuenta', onPressed: onRegister),
        const SizedBox(height: 14),
        SecondaryAction(label: 'Ya tengo una cuenta', onPressed: onLogin),
        const Padding(
          padding: EdgeInsets.only(top: 26),
          child: _LegalNote(),
        ),
      ],
    );
  }
}

/// "Al continuar aceptas nuestros Términos y la Política de privacidad."
class _LegalNote extends StatelessWidget {
  const _LegalNote();

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
