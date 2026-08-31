import 'package:flutter/material.dart';

import 'preferencias.dart';

/// Qué tema usa la app: el del teléfono, claro fijo u oscuro fijo.
///
/// Hasta ahora `main.dart` tenía `ThemeMode.system` escrito a mano con un
/// comentario que decía que en móvil la gente espera que se respete el ajuste
/// del sistema. Sigue siendo el valor por defecto —[ThemeMode.system] es la
/// opción inicial— pero ya no es la única: quien quiera la app siempre oscura
/// aunque su teléfono esté en claro puede elegirlo en Configuración.
///
/// La elección se guarda en el teléfono, no en Supabase. Si viviera en el
/// servidor haría falta una consulta antes del primer frame, y la pantalla
/// arrancaría en claro para saltar a oscuro medio segundo después.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _clave = 'ride.tema';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Lee la preferencia guardada. Se llama al arrancar, antes de pintar.
  void cargar() {
    _mode = _desdeId(Preferencias.instance.leer(_clave));
  }

  Future<void> cambiar(ThemeMode modo) async {
    if (_mode == modo) return;
    _mode = modo;
    notifyListeners();
    await Preferencias.instance.guardar(_clave, _id(modo));
  }

  /// Nombre de la opción tal como se muestra en Configuración.
  static String etiqueta(ThemeMode modo) => switch (modo) {
        ThemeMode.system => 'El del sistema',
        ThemeMode.light => 'Claro',
        ThemeMode.dark => 'Oscuro',
      };

  static String detalle(ThemeMode modo) => switch (modo) {
        ThemeMode.system => 'Sigue el ajuste de tu teléfono',
        ThemeMode.light => 'Siempre claro, aunque el teléfono esté en oscuro',
        ThemeMode.dark => 'Siempre oscuro, aunque el teléfono esté en claro',
      };

  static IconData icono(ThemeMode modo) => switch (modo) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  static String _id(ThemeMode modo) => switch (modo) {
        ThemeMode.system => 'sistema',
        ThemeMode.light => 'claro',
        ThemeMode.dark => 'oscuro',
      };

  static ThemeMode _desdeId(String? id) => switch (id) {
        'claro' => ThemeMode.light,
        'oscuro' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
