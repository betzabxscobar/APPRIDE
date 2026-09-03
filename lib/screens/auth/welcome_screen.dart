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
    final ride = context.ride;

    return AuthCard(
      children: [
        const AuthEyebrow('BIENVENIDO A RIDE'),
        const AuthHeading('¿Cómo quieres continuar?'),
        const AuthLead(
          'Elige una opción. Podrás configurar tu perfil después de entrar.',
          bottomSpacing: 24,
        ),
        _AccessOption(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Crear cuenta',
          description: 'Soy nuevo y quiero empezar a usar Ride.',
          emphasized: true,
          onPressed: onRegister,
        ),
        const SizedBox(height: 12),
        _AccessOption(
          icon: Icons.login_rounded,
          title: 'Ya tengo una cuenta',
          description: 'Quiero entrar con mi correo y contraseña.',
          onPressed: onLogin,
        ),
        Padding(padding: const EdgeInsets.only(top: 24), child: _LegalNote()),
        const SizedBox(height: 4),
        Divider(color: ride.border),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: ride.inkFaint),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'Tus datos se protegen durante el acceso.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ride.inkFaint,
                  fontSize: AppText.micro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccessOption extends StatelessWidget {
  const _AccessOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final foreground = emphasized && !ride.isDark ? Colors.white : ride.ink;
    final secondary = emphasized && !ride.isDark
        ? Colors.white.withValues(alpha: 0.78)
        : ride.inkMuted;

    return Material(
      color: emphasized
          ? (ride.isDark ? ride.accentSoft : ride.accent)
          : ride.surfaceAlt,
      borderRadius: BorderRadius.circular(AppTheme.radiusAction),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusAction),
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusAction),
            border: Border.all(
              color: emphasized ? ride.accent : ride.border,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: emphasized
                      ? Colors.white.withValues(
                          alpha: ride.isDark ? 0.08 : 0.16,
                        )
                      : ride.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: emphasized && !ride.isDark
                      ? Colors.white
                      : ride.accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: AppText.body,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: secondary,
                        fontSize: AppText.micro,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                color: emphasized && !ride.isDark ? Colors.white : ride.accent,
                size: 21,
              ),
            ],
          ),
        ),
      ),
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
