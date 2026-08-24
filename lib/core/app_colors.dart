import 'package:flutter/material.dart';

/// Paleta de la marca Ride, tomada del diseño de referencia.
abstract final class AppColors {
  static const Color primary = Color(0xFF2E90FA);
  static const Color primaryDark = Color(0xFF1B6FD0);
  static const Color primarySoft = Color(0xFFEAF4FF);

  static const Color green = Color(0xFF22C79B);
  static const Color greenSoft = Color(0xFFE8F8F2);

  static const Color purple = Color(0xFF7C6BF5);
  static const Color purpleSoft = Color(0xFFEFEDFE);

  static const Color ink = Color(0xFF0F2233);
  static const Color inkMuted = Color(0xFF64748B);

  static const Color background = Color(0xFFF7FAFF);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8F0);

  static const Color danger = Color(0xFFE5484D);

  /// Degradado suave usado en la pantalla de bienvenida.
  static const LinearGradient welcomeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE9F4FF), Color(0xFFF7FAFF)],
  );
}
