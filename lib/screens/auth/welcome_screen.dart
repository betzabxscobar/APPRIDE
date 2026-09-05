import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/ride_logo.dart';

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
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.height < 720 || screen.width < 360;
    final scale = compact ? 0.7 : 1.0;
    double space(double value) => value * scale;

    return AuthCard(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: RideWordmark(
            markSize: compact ? 56 : 64,
            fontSize: compact ? 24 : 27,
            color: Colors.white,
            subtitle: 'Muévete con libertad',
            subtitleColor: const Color(0xFFD5DCE3),
          ),
        ),
        SizedBox(height: space(34)),
        const Align(
          alignment: Alignment.center,
          child: Text(
            'BIENVENIDO A RIDE',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: AppText.micro,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        SizedBox(height: space(5)),
        Transform.translate(
          offset: Offset.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WelcomeHeading(
                topPadding: space(30),
                continuationIndent: compact ? 50 : 80,
              ),
              _WelcomeLead(
                topSpacing: space(20),
                bottomSpacing: space(39),
              ),
              _AccessOption(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Crear cuenta',
                description: 'Soy nuevo y quiero empezar a usar Ride.',
                emphasized: true,
                compact: compact,
                onPressed: onRegister,
              ),
              SizedBox(height: space(30)),
              _AccessOption(
                icon: Icons.account_circle_outlined,
                title: 'Ya tengo una cuenta',
                description: 'Quiero entrar con mi correo y contraseña.',
                compact: compact,
                onPressed: onLogin,
              ),
            ],
          ),
        ),
        SizedBox(height: space(74)),
        const _SecurityDivider(),
        Padding(
          padding: EdgeInsets.only(top: space(18)),
          child: const _LegalNote(),
        ),
      ],
    );
  }
}

class _WelcomeLead extends StatelessWidget {
  const _WelcomeLead({
    required this.topSpacing,
    required this.bottomSpacing,
  });

  final double topSpacing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Elige una opción\n',
              style: TextStyle(fontSize: AppText.body, color: ride.inkMuted),
            ),
            TextSpan(
              text: 'Podrás configurar tu perfil después de entrar.',
              style: TextStyle(fontSize: 13, color: ride.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityDivider extends StatelessWidget {
  const _SecurityDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: Color(0xFF00E5FF), thickness: 1.3),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Tus datos se protegen en el proceso',
                  style: TextStyle(
                    color: Color(0xFFD5DCE3),
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 5),
                Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: Color(0xFF00E5FF),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Divider(color: Color(0xFF00E5FF), thickness: 1.3),
        ),
      ],
    );
  }
}

class _WelcomeHeading extends StatelessWidget {
  const _WelcomeHeading({
    required this.topPadding,
    required this.continuationIndent,
  });

  final double topPadding;
  final double continuationIndent;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTheme.display(
      AppText.h1,
      color: context.ride.ink,
      letterSpacing: -0.9,
      height: 1.05,
    );
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¿Cómo quieres', style: baseStyle),
          Padding(
            padding: EdgeInsets.only(left: continuationIndent),
            child: Text(
              'continuar?',
              style: baseStyle.copyWith(
                fontSize: 34,
                color: const Color(0xFF00E5FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessOption extends StatelessWidget {
  const _AccessOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    required this.compact,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;
  final bool compact;
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
          constraints: BoxConstraints(minHeight: compact ? 74 : 82),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 11 : 14,
          ),
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
                  color: const Color(0xFF081F2D),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF00E5FF),
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
