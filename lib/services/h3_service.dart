import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:h3_dart/h3_dart.dart';

/// Celdas hexagonales H3 para la búsqueda de choferes por zona.
///
/// **Solo funciona en web, y es a propósito.** `h3_dart` elige implementación
/// según la plataforma:
///
/// - Web → `h3_web`, que son enlaces a la librería `h3-js`. Basta cargar el
///   script en `web/index.html`.
/// - Móvil y escritorio → FFI sobre la librería C de Uber, que hay que
///   compilar para cada plataforma. Eso todavía no está integrado.
///
/// Donde H3 no está disponible, [celda] y [disco] devuelven `null` y la app
/// cae a la búsqueda por radio de PostGIS. Las dos vías conviven en la base:
/// la política de difusión acepta cualquiera de las dos.
///
/// ## Por qué el servidor no puede verificar estas celdas
///
/// H3 no está entre las extensiones de Supabase, así que la celda la calcula
/// este dispositivo y viaja ya resuelta. Postgres comprueba el formato, pero no
/// puede confirmar que corresponda a las coordenadas enviadas. Con PostGIS esa
/// verificación ocurre dentro de la base. Es el precio de esta vía.
class H3Service {
  H3Service._();

  static final H3Service instance = H3Service._();

  /// Resolución para difundir solicitudes: arista de ~1,4 km.
  ///
  /// Medido sobre 40 choferes alrededor de un punto, con radio de 5 km:
  /// res 7 envía 61 celdas; res 8 sube a 331 y res 9 a 1.951, **sin ganar
  /// precisión**. Los hexágonos son de tamaño fijo, así que el disco siempre
  /// cubre más área que el círculo pedido.
  static const int resDifusion = 7;

  /// Resolución fina para agrupar por zonas y mapas de calor.
  static const int resZona = 9;

  /// Radio de difusión en kilómetros. Debe coincidir con
  /// `public.radio_busqueda_km()` para que las dos vías se comporten igual.
  static const double radioKm = 5;

  H3? _h3;
  bool _intentado = false;

  /// `null` si H3 no está disponible en esta plataforma.
  H3? get _motor {
    if (_intentado) return _h3;
    _intentado = true;

    if (!kIsWeb) return null;
    try {
      _h3 = const H3Factory().web();
    } catch (_) {
      // El script de h3-js no cargó. No es fatal: se usa PostGIS.
      _h3 = null;
    }
    return _h3;
  }

  bool get disponible => _motor != null;

  /// Celda que contiene ese punto, a la resolución pedida.
  String? celda(double lat, double lng, {int? resolucion}) {
    final h3 = _motor;
    if (h3 == null) return null;
    try {
      return h3
          .geoToCell(GeoCoord(lat: lat, lon: lng), resolucion ?? resDifusion)
          .toRadixString(16);
    } catch (_) {
      return null;
    }
  }

  /// Celda fina, para agrupar por zona.
  String? celdaZona(double lat, double lng) =>
      celda(lat, lng, resolucion: resZona);

  /// Todas las celdas dentro del radio de difusión alrededor de un punto.
  ///
  /// Es lo que se guarda en el viaje al solicitarlo: la política RLS no puede
  /// calcularlo por su cuenta, así que necesita el conjunto ya resuelto.
  List<String>? disco(double lat, double lng) {
    final h3 = _motor;
    if (h3 == null) return null;
    try {
      final arista = h3.getHexagonEdgeLengthAvg(resDifusion, H3MetricUnits.km);
      // Cuántos anillos hacen falta para alcanzar el radio.
      final anillos = (radioKm / arista).ceil();
      return h3
          .gridDisk(
            h3.geoToCell(GeoCoord(lat: lat, lon: lng), resDifusion),
            anillos,
          )
          .map((c) => c.toRadixString(16))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
