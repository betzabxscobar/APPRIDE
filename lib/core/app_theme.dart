import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'ride_colors.dart';

/// Tipografías de la marca: las mismas que WEB-RIDE carga desde Google Fonts.
///
/// Los `.ttf` viven en `assets/fonts` y se declaran en `pubspec.yaml`.
abstract final class AppFonts {
  /// Títulos y marca (`.brand-copy h1`, `.auth-box h2`, `.wordmark`).
  static const String display = 'Sora';

  /// Cuerpo de texto, etiquetas y botones.
  static const String body = 'PlusJakartaSans';
}

/// Escala tipográfica de la app.
///
/// La web usaba 10–15 px porque se lee a medio metro con un ratón. En un
/// teléfono, a un palmo y con el pulgar, esos tamaños se leen apretados y los
/// controles quedan chicos para el dedo. Esta escala arranca en 13 px para lo
/// accesorio y pone el cuerpo en 16, que es lo que usan de base tanto iOS como
/// Android.
abstract final class AppText {
  /// Titular del héroe.
  static const double hero = 34;

  /// Título de pantalla o de formulario.
  static const double h1 = 27;

  /// Título de bloque.
  static const double h2 = 20;

  /// Título de tarjeta.
  static const double h3 = 17;

  /// Cuerpo por defecto.
  static const double body = 16;

  /// Cuerpo secundario y bajadas.
  static const double small = 14.5;

  /// Etiquetas de campo, chips, metadatos.
  static const double label = 13;

  /// Lo verdaderamente accesorio: nota legal, atribución del mapa.
  static const double micro = 12;
}

abstract final class AppTheme {
  static const double radius = 18;
  static const double radiusLarge = 24;

  /// Radio de los campos y de los botones.
  ///
  /// La web usaba 10 y 12 px. En el teléfono, con controles más altos, ese
  /// radio deja las esquinas casi rectas y el conjunto se ve a formulario de
  /// página web.
  static const double radiusField = 14;
  static const double radiusAction = 16;

  /// Radio superior de las hojas que suben desde abajo.
  static const double radiusSheet = 28;

  /// Alto mínimo de un control que se toca con el dedo.
  static const double tapTarget = 56;

  /// Ancho máximo de `.auth-box`.
  static const double authBoxWidth = 450;

  /// `@media(max-width:850px)`: bajo este ancho se oculta el panel de marca.
  static const double wideBreakpoint = 850;

  /// Título con la tipografía de display.
  ///
  /// El color por defecto sigue siendo la constante clara para no romper a
  /// quien la llame sin contexto; las pantallas ya migradas le pasan
  /// `context.ride.ink`.
  static TextStyle display(
    double size, {
    Color color = AppColors.ink,
    double letterSpacing = -1.2,
    double height = 1.15,
    FontWeight weight = FontWeight.w800,
  }) {
    return TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static ThemeData get light => _build(RideColors.light);

  static ThemeData get dark => _build(RideColors.dark);

  static ThemeData _build(RideColors ride) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: ride.brightness,
      fontFamily: AppFonts.body,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: ride.brightness,
        primary: ride.accent,
        onPrimary: ride.isDark ? const Color(0xFF04121C) : Colors.white,
        secondary: ride.success,
        surface: ride.surface,
        onSurface: ride.ink,
        error: ride.danger,
      ),
      scaffoldBackgroundColor: ride.background,
    );

    return base.copyWith(
      extensions: [ride],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: ride.ink,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: ride.ink,
          fontSize: AppText.h3,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: ride.ink,
        displayColor: ride.ink,
      ),
      iconTheme: IconThemeData(color: ride.inkMuted, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ride.isDark
            ? const Color(0xFF1C5874)
            : const Color(0xFFE3F6FF),
        // 18 px de alto interior dejan el campo en ~56: el mínimo cómodo para
        // tocar sin fallar.
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: TextStyle(color: ride.inkFaint, fontSize: AppText.body),
        border: _inputBorder(ride.border),
        enabledBorder: _inputBorder(ride.border),
        focusedBorder: _inputBorder(ride.accent, width: 1.8),
        errorBorder: _inputBorder(ride.danger),
        focusedErrorBorder: _inputBorder(ride.danger, width: 1.8),
        errorStyle: TextStyle(
          fontSize: AppText.label,
          fontWeight: FontWeight.w600,
          color: ride.dangerInk,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ride.accent,
          foregroundColor: ride.isDark ? const Color(0xFF04121C) : Colors.white,
          minimumSize: const Size.fromHeight(tapTarget),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: AppText.body,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusAction),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ride.ink,
          minimumSize: const Size.fromHeight(tapTarget),
          side: BorderSide(color: ride.border, width: 1.4),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: AppText.body,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusAction),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ride.accent,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: AppText.small,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ride.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: ride.accentSoft,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: AppFonts.body,
            fontSize: AppText.micro,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? ride.accent
                : ride.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 25,
            color: states.contains(WidgetState.selected)
                ? ride.accent
                : ride.inkMuted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ride.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: ride.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusSheet)),
        ),
      ),
      dividerTheme: DividerThemeData(color: ride.border, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : ride.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ride.accent
              : ride.surfaceSunken,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ride.isDark ? ride.surfaceAlt : const Color(0xFF13293D),
        contentTextStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: AppText.small,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusAction),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ride.accent),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.4}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusField),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
