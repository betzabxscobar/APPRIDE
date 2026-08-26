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

  /// Coordenadas actuales.
  ///
  /// Lanza [LocationUnavailable] con un mensaje explicando qué falta: el GPS
  /// apagado y el permiso denegado se resuelven de formas distintas y conviene
  /// decir cuál es.
  Future<({double lat, double lng})> posicionActual() async {
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
    return (lat: posicion.latitude, lng: posicion.longitude);
  }
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}
