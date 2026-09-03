import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colores que cambian con el tema.
///
/// [AppColors] guarda la marca —el azul, el verde, el morado, el navy— que es
/// la misma de día y de noche. Aquí viven los neutros: fondos, superficies,
/// textos y bordes. Esos sí se dan la vuelta cuando el teléfono está en modo
/// oscuro, y por eso no pueden ser constantes sueltas repartidas por las
/// pantallas.
///
/// Se lee con `context.ride`, nunca con `AppColors.ink` directamente. Toda la
/// app está migrada: si aparece un neutro escrito a mano en una pantalla, es un
/// color que se quedará fijo cuando el teléfono cambie de tema.
@immutable
class RideColors extends ThemeExtension<RideColors> {
  const RideColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.info,
    required this.infoSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerInk,
    required this.shadow,
  });

  final Brightness brightness;

  /// Fondo de la pantalla.
  final Color background;

  /// Tarjetas, hojas y campos.
  final Color surface;

  /// Relleno sutil: chips, avatares, campos dentro de una tarjeta.
  final Color surfaceAlt;

  /// Un escalón por debajo del fondo, para hundir bloques.
  final Color surfaceSunken;

  /// Texto principal.
  final Color ink;

  /// Texto secundario. Cumple contraste AA sobre [surface] y [background].
  final Color inkMuted;

  /// Texto terciario: notas legales, pies, marcas de tiempo.
  final Color inkFaint;

  final Color border;
  final Color borderStrong;

  /// Azul de marca ajustado al tema: en oscuro se aclara para que se lea.
  final Color accent;
  final Color accentSoft;

  final Color success;
  final Color successSoft;

  final Color info;
  final Color infoSoft;

  final Color danger;
  final Color dangerSoft;
  final Color dangerInk;

  /// Color de las sombras. En oscuro casi no se ven, así que se usan más
  /// opacas y el relieve se apoya sobre todo en el borde.
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Degradado del héroe de las pantallas de acceso.
  ///
  /// El tema oscuro usa azules medios de alto contraste. No representa la
  /// noche: solo reduce el brillo de la superficie sin perder la identidad ni
  /// convertir las ilustraciones en siluetas casi negras.
  LinearGradient get hero => isDark ? _heroDark : AppColors.brandPanel;

  static const LinearGradient _heroDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0, 0.52, 1],
    colors: [Color(0xFF0A3047), Color(0xFF0D4962), Color(0xFF12657B)],
  );

  static const RideColors light = RideColors(
    brightness: Brightness.light,
    // Un punto más profundo que el #F7FAFF de la web: sobre un fondo casi
    // blanco las tarjetas blancas no llegaban a despegarse.
    background: Color(0xFFF1F5FA),
    surface: Colors.white,
    surfaceAlt: Color(0xFFF4F8FC),
    surfaceSunken: Color(0xFFE7EEF6),
    ink: Color(0xFF0A1930),
    // El #6C7C8D de la web daba 3.6:1 sobre blanco, por debajo de AA. Este da
    // 5.9:1 y se sigue leyendo como gris, no como negro.
    inkMuted: Color(0xFF52657B),
    inkFaint: Color(0xFF77879A),
    border: Color(0xFFD9E4EF),
    borderStrong: Color(0xFFBECEDD),
    accent: AppColors.primary,
    accentSoft: AppColors.primarySoft,
    success: Color(0xFF0F9B78),
    successSoft: AppColors.greenSoft,
    info: AppColors.purple,
    infoSoft: AppColors.purpleSoft,
    danger: AppColors.danger,
    dangerSoft: AppColors.errorBackground,
    dangerInk: AppColors.errorInk,
    shadow: Color(0x1A0A1930),
  );

  /// Oscuro construido sobre el navy de la marca, no sobre gris neutro: así el
  /// modo oscuro sigue pareciendo Ride y no una app cualquiera.
  static const RideColors dark = RideColors(
    brightness: Brightness.dark,
    background: Color(0xFF061420),
    surface: Color(0xFF0E2432),
    surfaceAlt: Color(0xFF143143),
    surfaceSunken: Color(0xFF030C14),
    ink: Color(0xFFE9F3FA),
    inkMuted: Color(0xFF9CB2C4),
    inkFaint: Color(0xFF7A91A5),
    border: Color(0xFF1E3D52),
    borderStrong: Color(0xFF2C566F),
    // El azul de marca sobre fondo oscuro queda flojo; se sube el brillo sin
    // moverle el tono.
    accent: Color(0xFF56B6F8),
    accentSoft: Color(0xFF12354C),
    success: Color(0xFF3FD9AC),
    successSoft: Color(0xFF0D3A32),
    info: Color(0xFF9C8EF9),
    infoSoft: Color(0xFF241F4A),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0xFF3A1A1C),
    dangerInk: Color(0xFFFFB4AE),
    shadow: Color(0x66000000),
  );

  @override
  RideColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunken,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? info,
    Color? infoSoft,
    Color? danger,
    Color? dangerSoft,
    Color? dangerInk,
    Color? shadow,
  }) {
    return RideColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      dangerInk: dangerInk ?? this.dangerInk,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  RideColors lerp(covariant RideColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;

    return RideColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkFaint: mix(inkFaint, other.inkFaint),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      info: mix(info, other.info),
      infoSoft: mix(infoSoft, other.infoSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      dangerInk: mix(dangerInk, other.dangerInk),
      shadow: mix(shadow, other.shadow),
    );
  }
}

extension RideColorsContext on BuildContext {
  /// Tokens del tema activo.
  ///
  /// El `??` no es paranoia: las pruebas de widgets montan pantallas sueltas y
  /// alguna puede llegar sin la extensión puesta. Antes que romper, se asume
  /// claro.
  RideColors get ride =>
      Theme.of(this).extension<RideColors>() ?? RideColors.light;
}
