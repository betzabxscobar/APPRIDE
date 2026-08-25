import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Mensaje de error del formulario, igual al bloque `.error` de WEB-RIDE.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 11,
          height: 1.45,
          color: AppColors.errorInk,
          fontWeight: FontWeight.w600,
        ),
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
