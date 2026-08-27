import 'package:latlong2/latlong.dart' show LatLng;

import '../services/location_service.dart';

/// Encuadre inicial del mapa cuando todavía no se sabe dónde está la persona.
///
/// Antes cada pantalla tenía escrito a mano `LatLng(-2.1709, -79.9224)`
/// —Guayaquil— como relleno. Eso hacía dos cosas mal a la vez: enseñaba un mapa
/// de otra ciudad como si fuera la tuya, y sesgaba la búsqueda de direcciones
/// hacia allí, así que a alguien en Quito le salían calles que no conoce o que
/// no existen cerca.
///
/// Ahora manda la última posición leída. Solo si no hay ninguna se cae a una
/// vista de país, que es honesta: se ve que es un encuadre general y no una
/// afirmación sobre dónde estás.
abstract final class MapDefaults {
  /// Centro aproximado de Ecuador. La app opera aquí: sus pantallas hablan de
  /// Quito y Guayaquil y las tarifas son locales.
  static const LatLng centroPais = LatLng(-1.5, -78.5);

  /// Zoom de país: suficiente para verlo entero sin insinuar una posición.
  static const double zoomPais = 6;

  /// Zoom de calle, para cuando sí sabemos dónde estamos.
  static const double zoomCalle = 15.5;

  /// Dónde centrar el mapa ahora mismo.
  static LatLng get centro {
    final ultima = LocationService.instance.ultimaConocida;
    return ultima == null ? centroPais : LatLng(ultima.lat, ultima.lng);
  }

  /// Zoom que corresponde a [centro].
  static double get zoom =>
      LocationService.instance.ultimaConocida == null ? zoomPais : zoomCalle;

  /// Punto con el que sesgar la búsqueda de direcciones.
  ///
  /// `null` cuando no se sabe nada: es preferible una búsqueda mundial a una
  /// sesgada hacia una ciudad equivocada.
  static ({double lat, double lng})? get referenciaBusqueda =>
      LocationService.instance.ultimaConocida;
}
