import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/user_role.dart';
import '../../widgets/ride_logo.dart';
import '../../widgets/role_selector.dart';
import 'login_screen.dart';

/// Primera pantalla: marca, propuesta de valor y elección de rol.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  UserRole? _role;

  void _continue() {
    final role = _role;
    if (role == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(role: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.welcomeGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      const RideLogo(),
                      const SizedBox(height: 36),
                      const _ValueProps(),
                      const SizedBox(height: 36),
                      const Text(
                        'Elige cómo quieres usar Ride',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (final role in UserRole.selectable) ...[
                            Expanded(
                              child: RoleCard(
                                role: role,
                                selected: _role == role,
                                onTap: () => setState(() => _role = role),
                              ),
                            ),
                            if (role != UserRole.selectable.last)
                              const SizedBox(width: 12),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _role == null ? null : _continue,
                        child: const Text('Continuar'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _role == null
                            ? 'Selecciona una opción para continuar'
                            : 'Podrás cambiar de rol más adelante',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ValueProps extends StatelessWidget {
  const _ValueProps();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ValueProp(
          icon: Icons.verified_user_outlined,
          color: AppColors.green,
          background: AppColors.greenSoft,
          title: 'Seguro',
          subtitle: 'Tecnología que te cuida.',
        ),
        SizedBox(height: 16),
        _ValueProp(
          icon: Icons.eco_outlined,
          color: AppColors.green,
          background: AppColors.greenSoft,
          title: 'Sostenible',
          subtitle: 'Menos emisiones, más futuro.',
        ),
        SizedBox(height: 16),
        _ValueProp(
          icon: Icons.favorite_outline,
          color: AppColors.primary,
          background: AppColors.primarySoft,
          title: 'Confiable',
          subtitle: 'Personas reales, viajes mejores.',
        ),
      ],
    );
  }
}

class _ValueProp extends StatelessWidget {
  const _ValueProp({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, size: 21, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
