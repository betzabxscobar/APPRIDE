import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../widgets/auth_widgets.dart';

/// Bienvenida (`.welcome-box` de WEB-RIDE): la puerta de entrada al registro
/// y al inicio de sesión.
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
        const AuthHeading('Tu próximo viaje\nempieza aquí.', size: 42),
        const AuthLead(
          'Crea una cuenta o inicia sesión para continuar.',
          bottomSpacing: 35,
        ),
        PrimaryAction(label: 'Crear cuenta', onPressed: onRegister),
        const SizedBox(height: 12),
        SecondaryAction(label: 'Ya tengo una cuenta', onPressed: onLogin),
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: _LegalNote(),
        ),
      ],
    );
  }
}

/// "Al continuar aceptas nuestros Términos y la Política de privacidad."
class _LegalNote extends StatelessWidget {
  const _LegalNote();

  static const TextStyle _link = TextStyle(
    color: AppColors.link,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.link,
  );

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Al continuar aceptas nuestros '),
          TextSpan(text: 'Términos', style: _link),
          TextSpan(text: ' y la '),
          TextSpan(text: 'Política de privacidad', style: _link),
          TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, height: 1.6, color: Color(0xFF96A3AD)),
    );
  }
}
