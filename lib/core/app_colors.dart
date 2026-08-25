import 'package:flutter/material.dart';

/// Paleta de la marca Ride.
///
/// Los tokens replican las variables CSS de WEB-RIDE (`src/App.css`) para que
/// la bienvenida, el login y el registro se vean idénticos en web y en la app.
abstract final class AppColors {
  // --blue / --sky / --mint
  static const Color primary = Color(0xFF269DF3);
  static const Color primaryDark = Color(0xFF1B7FD0);
  static const Color primarySoft = Color(0xFFEEF8FF);
  static const Color sky = Color(0xFF69D2F0);

  static const Color green = Color(0xFF22C79B);
  static const Color greenSoft = Color(0xFFE1F8F3);
  static const Color mint = Color(0xFF55CDB8);

  static const Color purple = Color(0xFF7C6BF5);
  static const Color purpleSoft = Color(0xFFEFEDFE);

  // --ink / --muted / --line / --paper
  static const Color ink = Color(0xFF0A1930);
  static const Color inkMuted = Color(0xFF6C7C8D);
  static const Color background = Color(0xFFF7FAFF);
  static const Color surface = Colors.white;
  static const Color paper = Color(0xFFFCFDFF);
  static const Color border = Color(0xFFDCE8EF);

  static const Color danger = Color(0xFFE5484D);

  /// Textos secundarios del formulario web: eyebrow, etiqueta, enlace y
  /// botón "Volver".
  static const Color eyebrow = Color(0xFF1A9FD3);
  static const Color fieldLabel = Color(0xFF33495A);
  static const Color link = Color(0xFF168DB9);
  static const Color backLink = Color(0xFF758595);
  static const Color footerText = Color(0xFF8794A0);
  static const Color rolePickerHint = Color(0xFF81909E);

  /// Bloque `.error` del formulario web.
  static const Color errorBackground = Color(0xFFFFF1EF);
  static const Color errorInk = Color(0xFFB54D41);
  static const Color errorBorder = Color(0xFFFFD8D2);

  // Panel de marca (columna oscura de la izquierda en escritorio).
  static const Color navy = Color(0xFF061823);
  static const Color navyMid = Color(0xFF0A293B);
  static const Color navyEnd = Color(0xFF10384D);
  static const Color navySoft = Color(0xFFB4C8D3);
  static const Color navyFaint = Color(0xFF91AEBE);

  /// `linear-gradient(145deg,#061823,#0a293b 52%,#10384d)`
  static const LinearGradient brandPanel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0, 0.52, 1],
    colors: [navy, navyMid, navyEnd],
  );

  /// `linear-gradient(135deg,#39b7f2,#238ff0)` — botón principal.
  static const LinearGradient primaryAction = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF39B7F2), Color(0xFF238FF0)],
  );

  /// `linear-gradient(145deg,#7ddbf2,#37b8ef)` — isotipo hexagonal.
  static const LinearGradient logo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7DDBF2), Color(0xFF37B8EF)],
  );

  /// `linear-gradient(145deg,#fff,#f8fbfc)` — fondo del panel del formulario.
  static const LinearGradient formPanel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, Color(0xFFF8FBFC)],
  );

  /// Degradado suave usado en pantallas internas.
  static const LinearGradient welcomeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE9F4FF), Color(0xFFF7FAFF)],
  );
}
