import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo poco que la app guarda en el teléfono.
///
/// La fuente de verdad sigue siendo Supabase: aquí no vive ningún dato que
/// decida algo. Solo dos cosas que tienen que sobrevivir a que se cierre la
/// app y que no valdría la pena ir a buscar por red:
///
/// - el tema elegido, porque leerlo del servidor haría parpadear la pantalla
///   entre claro y oscuro en cada arranque;
/// - el último viaje en marcha, para volver a abrirlo de inmediato mientras el
///   servidor confirma en qué estado quedó.
///
/// Se carga una sola vez al arrancar. Si `SharedPreferences` falla —pasa en
/// algunos navegadores con el almacenamiento bloqueado— la app sigue: cada
/// lectura devuelve el valor por defecto y cada escritura no hace nada.
class Preferencias {
  Preferencias._();

  static final Preferencias instance = Preferencias._();

  SharedPreferences? _prefs;

  /// Abre el almacén local. Se llama una vez, en `main()`, antes de pintar.
  ///
  /// Lleva tope de tiempo porque va delante del primer frame: si el plugin se
  /// quedara colgado, la app entera se quedaría en negro. Prefiero arrancar
  /// con el tema del sistema y sin viaje guardado que no arrancar.
  Future<void> cargar() async {
    try {
      _prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('No se pudieron abrir las preferencias locales: $e');
    }
  }

  String? leer(String clave) => _prefs?.getString(clave);

  Future<void> guardar(String clave, String valor) async {
    try {
      await _prefs?.setString(clave, valor);
    } catch (_) {
      // Que no se pueda guardar una preferencia nunca debe romper una pantalla.
    }
  }

  Future<void> borrar(String clave) async {
    try {
      await _prefs?.remove(clave);
    } catch (_) {}
  }
}
