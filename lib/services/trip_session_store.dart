import 'dart:convert';

import '../core/preferencias.dart';
import '../models/trip.dart';
import 'auth_service.dart';

/// Recuerda el viaje que estaba en marcha cuando se cerró la app.
///
/// El viaje de verdad vive en Postgres y ahí sigue estando aunque el teléfono
/// se apague; el problema era otro: al volver a abrir, la app arrancaba en la
/// bienvenida y no había nada que llevara de vuelta al viaje. Y aunque lo
/// hubiera, la pantalla se quedaba en blanco el segundo largo que tarda la
/// consulta, que con datos móviles flojos son varios.
///
/// Esto guarda una copia del último viaje activo para pintarla de inmediato al
/// arrancar. **No es una fuente de verdad**: en cuanto contesta el servidor se
/// reemplaza, y si el servidor dice que ese viaje ya terminó, se borra. Sirve
/// para no mirar una pantalla vacía, no para decidir nada.
class TripSessionStore {
  TripSessionStore._();

  static final TripSessionStore instance = TripSessionStore._();

  static const String _clave = 'ride.viaje_activo';

  /// De quién es el viaje guardado.
  ///
  /// Sin esto, dos cuentas en el mismo teléfono compartían el archivo: quien
  /// entraba después veía el viaje del anterior —con su origen, su destino y
  /// el nombre de su chofer— antes de que el servidor contestara. Datos de
  /// otra persona en tu pantalla.
  static const String _claveDueno = 'ride.viaje_activo.dueno';

  Trip? _cacheado;

  /// El viaje guardado, si lo hay y sigue teniendo pinta de estar vivo.
  Trip? get cacheado => _cacheado;

  /// Lee lo guardado. Se llama una vez al arrancar, antes del primer frame.
  void cargar() {
    final crudo = Preferencias.instance.leer(_clave);
    if (crudo == null) return;

    // Solo se restaura lo que es de esta cuenta.
    final dueno = Preferencias.instance.leer(_claveDueno);
    final yo = AuthService.instance.currentUser?.id;
    if (dueno == null || yo == null || dueno != yo) {
      limpiar();
      return;
    }

    try {
      final mapa = Map<String, dynamic>.from(jsonDecode(crudo) as Map);
      final viaje = Trip.fromMap(mapa);
      // Un viaje ya cerrado no tiene nada que reabrir. Puede quedar guardado
      // si la app se cerró justo entre el cambio de estado y el guardado.
      _cacheado = viaje.status.esActivo ? viaje : null;
      if (_cacheado == null) Preferencias.instance.borrar(_clave);
    } catch (_) {
      // Formato viejo o dato corrupto: se descarta sin ruido.
      Preferencias.instance.borrar(_clave);
    }
  }

  /// Guarda el viaje si sigue vivo; si ya terminó, borra lo que hubiera.
  Future<void> guardar(Trip? viaje) async {
    if (viaje == null || viaje.status.esFinal) {
      await limpiar();
      return;
    }
    final yo = AuthService.instance.currentUser?.id;
    if (yo == null) return;

    _cacheado = viaje;
    await Preferencias.instance.guardar(_clave, jsonEncode(viaje.toMap()));
    await Preferencias.instance.guardar(_claveDueno, yo);
  }

  /// Borra el viaje guardado. Se llama también al cerrar sesión: lo que quede
  /// aquí lo vería la siguiente cuenta que entre en este teléfono.
  Future<void> limpiar() async {
    _cacheado = null;
    await Preferencias.instance.borrar(_clave);
    await Preferencias.instance.borrar(_claveDueno);
  }
}
