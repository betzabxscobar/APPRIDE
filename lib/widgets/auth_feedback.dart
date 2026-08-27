import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Mensaje de error del formulario.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return _Banner(
      icon: Icons.error_outline,
      background: ride.dangerSoft,
      border: ride.danger.withValues(alpha: 0.4),
      foreground: ride.dangerInk,
      message: message,
    );
  }
}

/// Aviso informativo del formulario.
///
/// Mismo bloque que [ErrorBanner] pero en verde: se usa cuando la operación
/// salió bien y solo falta un paso, como el correo de confirmación tras
/// registrarse. Mostrar eso en rojo haría creer que el registro falló.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return _Banner(
      icon: Icons.check_circle_outline,
      background: ride.successSoft,
      border: ride.success.withValues(alpha: 0.45),
      foreground: ride.isDark ? ride.success : ride.ink,
      message: message,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
    required this.message,
  });

  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppText.small,
                height: 1.45,
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de carga con el tamaño correcto para ir dentro de un botón.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
    );
  }
}
