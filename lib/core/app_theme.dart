import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografías de la marca: las mismas que WEB-RIDE carga desde Google Fonts.
///
/// Los `.ttf` viven en `assets/fonts` y se declaran en `pubspec.yaml`.
abstract final class AppFonts {
  /// Títulos y marca (`.brand-copy h1`, `.auth-box h2`, `.wordmark`).
  static const String display = 'Sora';

  /// Cuerpo de texto, etiquetas y botones.
  static const String body = 'PlusJakartaSans';
}

abstract final class AppTheme {
  static const double radius = 16;
  static const double radiusLarge = 22;

  /// Radio de los controles del formulario web (`.auth-box input` = 10px,
  /// `.primary-action` = 12px).
  static const double radiusField = 10;
  static const double radiusAction = 12;

  /// Ancho máximo de `.auth-box`.
  static const double authBoxWidth = 450;

  /// `@media(max-width:850px)`: bajo este ancho se oculta el panel de marca.
  static const double wideBreakpoint = 850;

  /// Título estilo `.auth-box h2` / `.brand-copy h1`.
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

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppFonts.body,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(const Color(0xFF62BFDC), width: 1.6),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.6),
        errorStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.errorInk,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusAction),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.link,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusField),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
