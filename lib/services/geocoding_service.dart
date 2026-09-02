import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/busqueda_config.dart';

/// Un lugar del mundo, venga del geocodificador o de las direcciones guardadas.
class GeoPlace {
  const GeoPlace({
    required this.nombre,
    required this.direccion,
    required this.lat,
    required this.lng,
  });

  /// Lo que se muestra en grande: el nombre del sitio o la calle.
  final String nombre;

  /// La línea de contexto: ciudad, provincia, país.
  final String direccion;

  final double lat;
  final double lng;

  /// Texto que se guarda en el viaje.
  String get completo => direccion.isEmpty ? nombre : '$nombre, $direccion';
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

  // ---------------------------------------------------------------- TomTom
  //
  // Con clave se usa TomTom, que tiene cartografía propia. En Quito encuentra
  // sitios que OSM no conoce. Sin clave, nada de esto se ejecuta.

  static const String _tomtomBase = 'api.tomtom.com';

  Future<List<GeoPlace>> _buscarTomTom(
    String q,
    ({double lat, double lng})? cercaDe,
    int limite,
  ) async {
    final r = await _cliente
        .get(
          Uri.https(
            _tomtomBase,
            '/search/2/search/${Uri.encodeComponent(q)}.json',
            {
              'key': BusquedaConfig.tomtomKey,
              'limit': '$limite',
              'language': 'es-ES',
              // `typeahead` le dice que el texto puede estar a medio escribir.
              'typeahead': 'true',
              // Sin esto, «Terminal» devolvía tres aeropuertos de España antes
              // que nada de Ecuador. Ver BusquedaConfig.paisesServicio.
              'countrySet': BusquedaConfig.paisesServicio,
              // Sesgo, no filtro: sin `radius`, lo de fuera sigue apareciendo
              // más abajo. Es lo que hace que «terminal» devuelva la de tu
              // ciudad y no la de otro país.
              if (cercaDe != null) 'lat': '${cercaDe.lat}',
              if (cercaDe != null) 'lon': '${cercaDe.lng}',
            },
          ),
        )
        .timeout(const Duration(seconds: 8));

    if (r.statusCode != 200) {
      throw const GeocodingException(
        'El buscador de direcciones no respondió.',
      );
    }

    final datos = jsonDecode(r.body) as Map<String, dynamic>;
    final resultados = datos['results'] as List? ?? const [];

    return [
      for (final x in resultados.cast<Map<String, dynamic>>()) ?_desdeTomTom(x),
    ];
  }

  GeoPlace? _desdeTomTom(Map<String, dynamic> r) {
    final pos = r['position'] as Map<String, dynamic>?;
    if (pos == null) return null;

    final dir = (r['address'] as Map<String, dynamic>?) ?? const {};
    final completo = (dir['freeformAddress'] as String?) ?? '';
    final partes = completo.split(',').map((e) => e.trim()).toList();

    // Un punto de interés se nombra por su nombre; una calle, por su nombre de
    // calle. Si no hay ninguno, el primer trozo de la dirección completa.
    final poi = (r['poi'] as Map<String, dynamic>?)?['name'] as String?;
    final calle = dir['streetName'] as String?;
    final nombre =
        poi ?? calle ?? (partes.isEmpty ? 'Sin nombre' : partes.first);

    // El contexto es la dirección completa sin repetir lo que ya va de nombre.
    final resto = partes.isNotEmpty && partes.first == nombre
        ? partes.skip(1)
        : partes;

    return GeoPlace(
      nombre: nombre,
      direccion: resto.join(', '),
      lat: (pos['lat'] as num).toDouble(),
      lng: (pos['lon'] as num).toDouble(),
    );
  }

  Future<GeoPlace?> _direccionDeTomTom(double lat, double lng) async {
    final r = await _cliente
        .get(
          Uri.https(_tomtomBase, '/search/2/reverseGeocode/$lat,$lng.json', {
            'key': BusquedaConfig.tomtomKey,
            'language': 'es-ES',
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (r.statusCode != 200) return null;

    final lista =
        (jsonDecode(r.body) as Map<String, dynamic>)['addresses'] as List?;
    if (lista == null || lista.isEmpty) return null;

    final dir =
        (lista.first as Map<String, dynamic>)['address']
            as Map<String, dynamic>?;
    if (dir == null) return null;

    final completo = (dir['freeformAddress'] as String?) ?? '';
    final partes = completo.split(',').map((e) => e.trim()).toList();
    final nombre =
        (dir['streetName'] as String?) ??
        (partes.isEmpty ? 'Punto en el mapa' : partes.first);

    return GeoPlace(
      nombre: nombre,
      direccion:
          (partes.isNotEmpty && partes.first == nombre
                  ? partes.skip(1)
                  : partes)
              .join(', '),
      // Las coordenadas que se devuelven son las que se preguntaron: quien
      // llama ya decide si se queda con las suyas.
      lat: lat,
      lng: lng,
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

    if (BusquedaConfig.usaTomTom) {
      try {
        final r = await _buscarTomTom(q, cercaDe, limite);
        if (r.isNotEmpty) return r;
      } catch (_) {
        // Sin red, cuota agotada o clave revocada: se sigue con Photon en vez
        // de dejar a la persona sin buscador.
      }
    }

    // Dos pasadas: primero acotando a la ciudad de quien busca, y solo si eso
    // no devuelve nada, al país entero.
    //
    // El `lat`/`lon` de Photon es un sesgo flojo, no un filtro, y se lo come
    // cualquier coincidencia de nombre: buscando «Urbanización Alma Lojana
    // Baja» desde Quito devolvía cuatro urbanizaciones de España y ninguna de
    // Ecuador. Con el recuadro, lo de fuera deja de competir.
    if (cercaDe == null) {
      // Sin saber dónde está la persona no hay recuadro posible.
      return _photon(q, limite, null, acotar: false);
    }

    final cerca = await _photon(q, limite, cercaDe, acotar: true);
    if (cerca.isNotEmpty) return cerca;

    // Si por ahí no hay nada se amplía al país entero, pero **no al mundo**.
    // Un viaje en taxi a 9 000 km no existe, y ofrecer una calle de España
    // solo consigue que alguien la toque por error y el viaje salga absurdo.
    // Prefiero devolver vacío y que se elija el punto en el mapa.
    return _photon(q, limite, cercaDe, acotar: true, radio: _radioPais);
  }

  /// Media anchura del recuadro de búsqueda, en grados.
  ///
  /// Un grado son unos 111 km. El primero cubre ~165 km: la ciudad y sus
  /// valles. El segundo, ~1 100 km, que es Ecuador entero y algo más.
  static const double _radioCiudad = 1.5;
  static const double _radioPais = 10;

  Future<List<GeoPlace>> _photon(
    String q,
    int limite,
    ({double lat, double lng})? cercaDe, {
    required bool acotar,
    double radio = _radioCiudad,
  }) async {
    // Sin `lang`: Photon solo acepta en, de, fr e it, y con `lang=es`
    // responde 400. Los nombres llegan igual en el idioma local, que es lo
    // que se quiere («Avenida Amazonas», no «Amazonas Avenue»).
    final params = <String, String>{
      'q': q,
      'limit': '$limite',
      if (cercaDe != null) 'lat': '${cercaDe.lat}',
      if (cercaDe != null) 'lon': '${cercaDe.lng}',
      if (acotar && cercaDe != null)
        'bbox': [
          cercaDe.lng - radio,
          cercaDe.lat - radio,
          cercaDe.lng + radio,
          cercaDe.lat + radio,
        ].join(','),
    };

    try {
      final r = await _cliente
          .get(Uri.https(_base, '/api/', params), headers: _cabeceras)
          .timeout(const Duration(seconds: 8));

      if (r.statusCode != 200) {
        throw const GeocodingException(
          'El buscador de direcciones no respondió.',
        );
      }
      return _leerColeccion(r.body);
    } on TimeoutException {
      throw const GeocodingException('La búsqueda tardó demasiado. Reintenta.');
    } on GeocodingException {
      rethrow;
    } catch (_) {
      throw const GeocodingException(
        'Revisa tu conexión e inténtalo de nuevo.',
      );
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
    if (BusquedaConfig.usaTomTom) {
      try {
        final r = await _direccionDeTomTom(lat, lng);
        if (r != null) return r;
      } catch (_) {
        // Se prueba con Photon.
      }
    }

    try {
      final r = await _cliente
          .get(
            Uri.https(_base, '/reverse', {'lat': '$lat', 'lon': '$lng'}),
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
    final nombreBase = _nombreUtil(p);

    // Un resultado de calle con número se lee mejor como "Av. X 123" que como
    // el nombre suelto que devuelve el servicio.
    //
    // Si no hay ni nombre ni calle se baja al barrio y luego a la ciudad, que
    // dicen poco pero dicen algo. «Sin nombre» era el último recurso y salía
    // más de lo que debería.
    final nombre = nombreBase ??
        (calle != null
            ? (numero == null ? calle : '$calle $numero')
            : (p['district'] as String?) ??
                (p['city'] as String?) ??
                'Punto en el mapa');

    final contexto = [
      if (nombreBase != null && calle != null && calle != nombreBase)
        numero == null ? calle : '$calle $numero',
      p['district'] as String?,
      p['city'] as String?,
      p['state'] as String?,
      p['country'] as String?,
    ].whereType<String>().where((t) => t != nombre).toList();

    return GeoPlace(
      nombre: nombre,
      direccion: contexto.join(', '),
      lat: lat,
      lng: lng,
    );
  }

  /// El `name` que devuelve el servicio, solo si sirve como nombre de sitio.
  ///
  /// Photon devuelve también zonas postales, y su `name` es el propio código.
  /// Sin este filtro, tocar el mapa en La Carolina contestaba «170515» como si
  /// fuera una dirección: literalmente un número inventado a ojos de quien lo
  /// lee. Se descarta eso y cualquier nombre que sea solo cifras — un portal
  /// suelto tampoco es una dirección.
  static String? _nombreUtil(Map<String, dynamic> p) {
    final nombre = (p['name'] as String?)?.trim();
    if (nombre == null || nombre.isEmpty) return null;

    if (p['type'] == 'postcode' || p['osm_key'] == 'postal_code') return null;
    if (RegExp(r'^[0-9][0-9\s-]*$').hasMatch(nombre)) return null;

    return nombre;
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
