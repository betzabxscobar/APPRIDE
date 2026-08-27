import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Ubicación del dispositivo.
///
/// El GPS es del teléfono, no un servicio externo: no hay proveedor de mapas
/// detrás. Solo entrega coordenadas; convertirlas en una dirección legible
/// exigiría geocodificación, que sí sería un servicio de terceros. Por eso el
/// destino se elige del catálogo `public.lugares`.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  ({double lat, double lng})? _ultima;

  /// La última posición que se pudo leer, o `null` si aún no hay ninguna.
  ///
  /// Es lo que usan el mapa y el buscador de direcciones cuando todavía no hay
  /// una lectura fresca. Antes ese hueco lo tapaba Guayaquil escrito a mano, y
  /// el resultado era que a alguien en Quito le salían los lugares de otra
  /// ciudad —o directamente sitios que no existen cerca— porque el sesgo de
  /// búsqueda apuntaba a 400 km de distancia.
  ///
  /// Vive solo mientras la app está abierta: no se guarda en disco. Con que se
  /// lea una vez por sesión —los dos `home` la piden al arrancar— basta.
  ({double lat, double lng})? get ultimaConocida => _ultima;

  /// Coordenadas actuales y su margen de error en metros.
  ///
  /// Lanza [LocationUnavailable] con un mensaje explicando qué falta: el GPS
  /// apagado y el permiso denegado se resuelven de formas distintas y conviene
  /// decir cuál es.
  ///
  /// `precision` no es un dato de relleno: en un navegador de escritorio la
  /// posición no sale de un GPS sino de la IP o del wifi, y puede errar por
  /// kilómetros. Mostrarla deja ver de un vistazo si el punto es de fiar.
  ///
  /// Nunca se queda esperando para siempre: ver [_tope].
  Future<({double lat, double lng, double precision})> posicionActual() {
    return _leer().timeout(_tope, onTimeout: () {
      throw const LocationUnavailable(
        'No pudimos obtener tu ubicación a tiempo. '
        'Revisa que le hayas dado permiso a la app.',
      );
    });
  }

  /// Tope de toda la operación, no solo de la lectura del GPS.
  ///
  /// `getCurrentPosition` ya trae su propio límite, pero los pasos de antes no:
  /// si el navegador muestra el diálogo de permiso y nadie lo contesta,
  /// `requestPermission` no vuelve nunca y la pantalla se queda en «Buscando tu
  /// ubicación…» de forma permanente. Pasó de verdad en la build web.
  static const Duration _tope = Duration(seconds: 25);

  Future<({double lat, double lng, double precision})> _leer() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        'Activa la ubicación del dispositivo para pedir un viaje.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        'Diste permiso de ubicación como denegado permanentemente. '
        'Habilítalo desde los ajustes del teléfono.',
      );
    }
    if (permiso == LocationPermission.denied) {
      throw const LocationUnavailable(
        'Necesitamos tu ubicación para saber dónde recogerte.',
      );
    }

    final posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Sin tope, una lectura lenta deja la pantalla colgada sin explicación.
        timeLimit: Duration(seconds: 20),
      ),
    );
    _ultima = (lat: posicion.latitude, lng: posicion.longitude);

    return (
      lat: posicion.latitude,
      lng: posicion.longitude,
      precision: posicion.accuracy,
    );
  }
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}
