import 'dart:async';
import 'dart:convert';

import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/google_config.dart';

/// Un lugar del mundo, venga del geocodificador o de las direcciones guardadas.
class GeoPlace {
  const GeoPlace({
    required this.nombre,
    required this.direccion,
    required this.lat,
    required this.lng,
    this.placeId,
  });

  /// Lo que se muestra en grande: el nombre del sitio o la calle.
  final String nombre;

  /// La línea de contexto: ciudad, provincia, país.
  final String direccion;

  final double lat;
  final double lng;

  /// Identificador de Google, cuando la sugerencia viene de Places.
  ///
  /// El autocompletado de Google **no devuelve coordenadas**: hay que pedirlas
  /// aparte con este id. Mientras no se resuelva, [lat] y [lng] valen 0 — ver
  /// [necesitaResolver] y `GeocodingService.resolver`.
  final String? placeId;

  /// `true` si aún faltan las coordenadas reales.
  bool get necesitaResolver => placeId != null && lat == 0 && lng == 0;

  GeoPlace conCoordenadas(double nuevaLat, double nuevaLng) => GeoPlace(
        nombre: nombre,
        direccion: direccion,
        lat: nuevaLat,
        lng: nuevaLng,
        placeId: placeId,
      );

  /// Texto que se guarda en el viaje.
  String get completo =>
      direccion.isEmpty ? nombre : '$nombre, $direccion';
}

/// Búsqueda de direcciones en todo el mundo.
///
/// Usa Photon (https://photon.komoot.io), un geocodificador libre sobre datos
/// de OpenStreetMap. Cubre el planeta entero con sus calles y numeraciones.
///
/// **Por qué un servicio y no una tabla.** Los datos de calles del mundo pesan
/// cerca de un terabyte una vez importados a Postgres con sus índices; el plan
/// de Supabase da 500 MB. No es cuestión de configuración: no caben. Ninguna
/// app de transporte los guarda, todas consultan un geocodificador.
///
/// **Límite de uso.** El servidor de Photon lo dona Komoot y pide no abusar.
/// Para desarrollo y demos va bien. Con usuarios reales conviene auto-hospedar
/// Photon o pasar a Mapbox, que da 100.000 búsquedas al mes gratis. El cambio
/// afecta solo a esta clase.
class GeocodingService {
  GeocodingService._();

  static final GeocodingService instance = GeocodingService._();

  static const String _base = 'photon.komoot.io';

  /// Identifica a la app ante el servicio, como piden sus condiciones de uso.
  static const Map<String, String> _cabeceras = {
    'User-Agent': 'RideApp/1.0 (proyecto academico)',
  };

  final http.Client _cliente = http.Client();

  /// Evita disparar una petición por cada tecla: espera a que la persona deje
  /// de escribir.
  Timer? _espera;

  // ---------------------------------------------------------------- Google
  //
  // Con clave se usa Places de Google, que en Quito tiene bastantes mejores
  // datos que OSM. Sin clave, todo lo de abajo ni se toca.

  static const String _googleBase = 'places.googleapis.com';

  /// Sesión de facturación del autocompletado.
  ///
  /// Google cobra **por pulsación** si cada petición va suelta. Agrupándolas
  /// con un mismo token, todas las sugerencias de una búsqueda más la consulta
  /// de coordenadas del sitio elegido cuentan como **una sola sesión**. Es la
  /// diferencia entre pagar una vez o quince por la misma búsqueda.
  ///
  /// Se abre al empezar a escribir y se cierra en [resolver].
  String? _sesion;

  final Random _azar = Random();

  String _nuevaSesion() {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => abc[_azar.nextInt(abc.length)]).join();
  }

  Future<List<GeoPlace>> _buscarGoogle(
    String q,
    ({double lat, double lng})? cercaDe,
  ) async {
    _sesion ??= _nuevaSesion();

    final cuerpo = <String, dynamic>{
      'input': q,
      'sessionToken': _sesion,
      'languageCode': 'es',
      'regionCode': 'ec',
      if (cercaDe != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': cercaDe.lat, 'longitude': cercaDe.lng},
            // 30 km: cubre un área metropolitana sin encerrar la búsqueda.
            // Es sesgo, no filtro: lo de fuera sigue saliendo, más abajo.
            'radius': 30000.0,
          },
        },
    };

    final r = await _cliente
        .post(
          Uri.https(_googleBase, '/v1/places:autocomplete'),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': GoogleConfig.placesKey,
            // Sin espacios: la documentación lo dice expresamente. Y se piden
            // solo los campos que se usan, porque el campo pedido decide en qué
            // tramo de precio cae la llamada.
            'X-Goog-FieldMask':
                'suggestions.placePrediction.placeId,'
                'suggestions.placePrediction.structuredFormat',
          },
          body: jsonEncode(cuerpo),
        )
        .timeout(const Duration(seconds: 8));

    if (r.statusCode != 200) {
      throw const GeocodingException('El buscador de direcciones no respondió.');
    }

    final datos = jsonDecode(r.body) as Map<String, dynamic>;
    final sugerencias = datos['suggestions'] as List? ?? const [];

    return [
      for (final s in sugerencias)
        if ((s as Map<String, dynamic>)['placePrediction'] != null)
          _desdePrediccion(s['placePrediction'] as Map<String, dynamic>),
    ];
  }

  GeoPlace _desdePrediccion(Map<String, dynamic> p) {
    final formato = p['structuredFormat'] as Map<String, dynamic>?;
    final principal = (formato?['mainText'] as Map<String, dynamic>?)?['text'];
    final secundario =
        (formato?['secondaryText'] as Map<String, dynamic>?)?['text'];

    return GeoPlace(
      nombre: (principal as String?) ?? 'Sin nombre',
      direccion: (secundario as String?) ?? '',
      // Google no da coordenadas en el autocompletado: llegan en [resolver].
      lat: 0,
      lng: 0,
      placeId: p['placeId'] as String?,
    );
  }

  /// Completa las coordenadas de una sugerencia de Google.
  ///
  /// Cierra además la sesión de facturación: esta llamada entra en la misma
  /// sesión que las sugerencias que la precedieron, así que sale gratis dentro
  /// de ella. Con los lugares de Photon no hace nada, ya vienen con coordenadas.
  Future<GeoPlace> resolver(GeoPlace lugar) async {
    if (!lugar.necesitaResolver) return lugar;

    final sesion = _sesion;
    _sesion = null;

    final r = await _cliente
        .get(
          Uri.https(
            _googleBase,
            '/v1/places/${lugar.placeId}',
            {'sessionToken': ?sesion},
          ),
          headers: {
            'X-Goog-Api-Key': GoogleConfig.placesKey,
            // Solo la ubicación: es el campo más barato que existe.
            'X-Goog-FieldMask': 'location',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (r.statusCode != 200) {
      throw const GeocodingException('No pudimos ubicar esa dirección.');
    }

    final loc = (jsonDecode(r.body) as Map<String, dynamic>)['location']
        as Map<String, dynamic>?;
    if (loc == null) {
      throw const GeocodingException('No pudimos ubicar esa dirección.');
    }

    return lugar.conCoordenadas(
      (loc['latitude'] as num).toDouble(),
      (loc['longitude'] as num).toDouble(),
    );
  }

  // ---------------------------------------------------------------- Photon

  /// Busca direcciones que coincidan con [texto].
  ///
  /// Si se pasan [cercaDe], los resultados de esa zona salen primero. Es lo que
  /// hace que buscar «terminal» devuelva la de tu ciudad y no la de otro país.
  Future<List<GeoPlace>> buscar(
    String texto, {
    ({double lat, double lng})? cercaDe,
    int limite = 8,
  }) async {
    final q = texto.trim();
    if (q.length < 3) return const [];

    if (GoogleConfig.usaGoogle) {
      try {
        return await _buscarGoogle(q, cercaDe);
      } on GeocodingException {
        rethrow;
      } catch (_) {
        // Si Google falla —sin red, cuota agotada, clave revocada— se sigue
        // con Photon en vez de dejar al usuario sin buscador.
      }
    }

    // Sin `lang`: Photon solo acepta en, de, fr e it, y con `lang=es`
    // responde 400. Los nombres llegan igual en el idioma local, que es lo
    // que se quiere («Avenida Amazonas», no «Amazonas Avenue»).
    //
    // `lat`/`lon` no es un adorno: sin el sesgo, buscar «Avenida Amazonas»
    // desde Guayaquil devuelve la de Perú.
    final params = <String, String>{
      'q': q,
      'limit': '$limite',
      if (cercaDe != null) 'lat': '${cercaDe.lat}',
      if (cercaDe != null) 'lon': '${cercaDe.lng}',
    };

    try {
      final r = await _cliente
          .get(Uri.https(_base, '/api/', params), headers: _cabeceras)
          .timeout(const Duration(seconds: 8));

      if (r.statusCode != 200) {
        throw const GeocodingException('El buscador de direcciones no respondió.');
      }
      return _leerColeccion(r.body);
    } on TimeoutException {
      throw const GeocodingException('La búsqueda tardó demasiado. Reintenta.');
    } on GeocodingException {
      rethrow;
    } catch (_) {
      throw const GeocodingException('Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  /// Igual que [buscar], pero espera a que dejen de escribir.
  ///
  /// Devuelve `null` si otra pulsación canceló esta búsqueda: quien llama debe
  /// ignorar ese caso y no pintar nada.
  Future<List<GeoPlace>?> buscarConEspera(
    String texto, {
    ({double lat, double lng})? cercaDe,
    Duration espera = const Duration(milliseconds: 350),
  }) {
    _espera?.cancel();
    final completer = Completer<List<GeoPlace>?>();

    _espera = Timer(espera, () async {
      try {
        completer.complete(await buscar(texto, cercaDe: cercaDe));
      } catch (e) {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  /// Qué dirección corresponde a un punto del mapa.
  ///
  /// Es lo que permite tocar el mapa y que aparezca el nombre de la calle en
  /// vez de unas coordenadas.
  Future<GeoPlace?> direccionDe(double lat, double lng) async {
    try {
      final r = await _cliente
          .get(
            Uri.https(_base, '/reverse', {
              'lat': '$lat',
              'lon': '$lng',
            }),
            headers: _cabeceras,
          )
          .timeout(const Duration(seconds: 8));

      if (r.statusCode != 200) return null;
      final lugares = _leerColeccion(r.body);
      return lugares.isEmpty ? null : lugares.first;
    } catch (_) {
      // Sin nombre de calle el flujo sigue: se usan las coordenadas.
      return null;
    }
  }

  List<GeoPlace> _leerColeccion(String cuerpo) {
    final json = jsonDecode(cuerpo) as Map<String, dynamic>;
    final features = (json['features'] as List<dynamic>? ?? const []);

    final lugares = <GeoPlace>[];
    for (final f in features) {
      final lugar = _leerLugar(f as Map<String, dynamic>);
      if (lugar != null) lugares.add(lugar);
    }
    return lugares;
  }

  GeoPlace? _leerLugar(Map<String, dynamic> feature) {
    final geo = feature['geometry'] as Map<String, dynamic>?;
    final coords = geo?['coordinates'] as List<dynamic>?;
    if (coords == null || coords.length < 2) return null;

    // GeoJSON viene como [longitud, latitud]: invertirlo es un error clásico
    // que deja los puntos en medio del océano.
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final p = (feature['properties'] as Map<String, dynamic>?) ?? const {};

    final calle = p['street'] as String?;
    final numero = p['housenumber'] as String?;
    final nombreBase = p['name'] as String?;

    // Un resultado de calle con número se lee mejor como "Av. X 123" que como
    // el nombre suelto que devuelve el servicio.
    final nombre = nombreBase ??
        (calle == null
            ? 'Sin nombre'
            : (numero == null ? calle : '$calle $numero'));

    final contexto = [
      if (nombreBase != null && calle != null && calle != nombreBase)
        numero == null ? calle : '$calle $numero',
      p['district'] as String?,
      p['city'] as String?,
      p['state'] as String?,
      p['country'] as String?,
    ].whereType<String>().toList();

    return GeoPlace(
      nombre: nombre,
      direccion: contexto.join(', '),
      lat: lat,
      lng: lng,
    );
  }

  void cancelarEspera() {
    _espera?.cancel();
    _espera = null;
  }
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;

  @override
  String toString() => message;
}
