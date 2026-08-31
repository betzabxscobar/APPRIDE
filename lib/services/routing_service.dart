import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/preferencias.dart';

/// Trazado de la ruta por calles entre dos puntos.
///
/// Antes de esto el mapa unía origen y destino con una línea recta, que
/// atraviesa manzanas y ríos y no se parece al camino real. Esto pide el
/// recorrido de verdad a [OSRM](https://github.com/Project-OSRM/osrm-backend),
/// el motor de rutas sobre datos de OpenStreetMap.
///
/// ## Es solo para dibujar
///
/// La distancia y el tiempo que devuelve **no fijan el precio**. La tarifa la
/// calcula Postgres y ahí se queda: el cliente se puede manipular, así que no
/// puede ser quien diga cuánto cuesta un viaje. Aquí solo sirven para
/// enseñárselos a la persona.
///
/// ## El servidor
///
/// Por defecto usa el servidor de demostración público, que no pide clave pero
/// **no vale para producción**: su política lo limita a desarrollo, puede ir
/// lento y puede cortar. Lo mismo vale para el de FOSSGIS.
///
/// Para producción se levanta el propio con `osrm-backend` —ver `infra/osrm/`,
/// que ya trae todo preparado— y se apunta la app ahí:
///
/// ```sh
/// flutter build web --dart-define=OSRM_URL=https://rutas.tudominio.com
/// ```
///
/// Tiene que ser **https**: una app servida por https no puede llamar a http,
/// el navegador lo bloquea por contenido mixto.
class RoutingService {
  RoutingService._();

  static final RoutingService instance = RoutingService._();

  static const String _demo = 'https://router.project-osrm.org';

  static const String _configurado = String.fromEnvironment(
    'OSRM_URL',
    defaultValue: _demo,
  );

  static String get servidor => normalizar(_configurado);

  /// Deja la URL como la espera [entre]: sin espacios ni barra final, y con el
  /// servidor de demostración si viene vacía.
  ///
  /// Separada para poder probarla: [_configurado] es una constante de
  /// compilación y no se puede variar desde una prueba.
  static String normalizar(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.isEmpty ? _demo : u;
  }

  /// `true` mientras se siga usando un servidor público de cortesía.
  ///
  /// Ninguno de los dos vale para usuarios reales: son de desarrollo y pueden
  /// cortar. Ver `infra/osrm/` para levantar el propio.
  static bool get usaServidorPublico => esServidorPublico(servidor);

  static bool esServidorPublico(String url) =>
      url.contains('project-osrm.org') || url.contains('openstreetmap.de');

  /// Rutas ya calculadas, para no volver a pedirlas.
  ///
  /// Dos motivos, y el segundo es el que importa:
  ///
  /// 1. El recorrido entre dos puntos fijos no cambia mientras dura un viaje,
  ///    y estas pantallas se reconstruyen cada vez que el chofer reporta
  ///    posición.
  /// 2. Al reabrir la app después de cerrarla, la ruta del viaje en marcha
  ///    tiene que verse **ya**, no cuando conteste OSRM. Por eso la caché se
  ///    guarda en el teléfono y no solo en memoria.
  ///
  /// Se guardan pocas y se van tirando las viejas: son listas de cientos de
  /// puntos y esto es una preferencia, no una base de datos.
  static const String _claveCache = 'ride.rutas';
  static const int _maxEnCache = 8;

  final Map<String, Ruta> _cache = {};
  bool _cacheLeida = false;

  /// Clave del par origen–destino. Cinco decimales son ~1 m: de sobra para
  /// decidir que es el mismo trayecto, y evita fallar por el ruido del GPS.
  static String _clave(LatLng origen, LatLng destino) =>
      '${origen.latitude.toStringAsFixed(5)},'
      '${origen.longitude.toStringAsFixed(5)};'
      '${destino.latitude.toStringAsFixed(5)},'
      '${destino.longitude.toStringAsFixed(5)}';

  void _leerCache() {
    if (_cacheLeida) return;
    _cacheLeida = true;

    final crudo = Preferencias.instance.leer(_claveCache);
    if (crudo == null) return;
    try {
      final mapa = Map<String, dynamic>.from(jsonDecode(crudo) as Map);
      mapa.forEach((clave, valor) {
        final ruta = Ruta.desdeJson(Map<String, dynamic>.from(valor as Map));
        if (ruta != null) _cache[clave] = ruta;
      });
    } catch (_) {
      Preferencias.instance.borrar(_claveCache);
    }
  }

  Future<void> _guardarCache() async {
    // Las más nuevas se insertan al final; se recortan las primeras.
    while (_cache.length > _maxEnCache) {
      _cache.remove(_cache.keys.first);
    }
    await Preferencias.instance.guardar(
      _claveCache,
      jsonEncode({for (final e in _cache.entries) e.key: e.value.aJson()}),
    );
  }

  /// La ruta guardada para ese par, si existe. No sale a la red.
  ///
  /// La pintan las pantallas nada más abrirse, antes de pedir la de verdad.
  Ruta? enCache(LatLng origen, LatLng destino) {
    _leerCache();
    return _cache[_clave(origen, destino)];
  }

  /// Recorrido entre dos puntos, o `null` si no se pudo calcular.
  ///
  /// Nunca lanza: un fallo aquí no debe romper la pantalla, porque el mapa se
  /// entiende igual sin la línea. Quien llama decide si cae a la recta.
  ///
  /// [recordar] en `false` salta la caché por completo. Es lo que usa el tramo
  /// del chofer hacia el punto de recogida: su origen es una posición que se
  /// mueve, así que guardarla llenaría la caché de rutas de un solo uso y
  /// echaría fuera la del viaje, que sí hay que poder repintar al reabrir.
  Future<Ruta?> entre(
    LatLng origen,
    LatLng destino, {
    bool recordar = true,
  }) async {
    if (!recordar) return _pedirRuta(origen, destino);

    _leerCache();
    final clave = _clave(origen, destino);
    final guardada = _cache[clave];
    if (guardada != null) return guardada;

    final calculada = await _pedirRuta(origen, destino);
    if (calculada != null) {
      _cache[clave] = calculada;
      await _guardarCache();
    }
    return calculada;
  }

  Future<Ruta?> _pedirRuta(LatLng origen, LatLng destino) async {
    // OSRM espera longitud,latitud — al revés que casi todo lo demás.
    final coords = '${origen.longitude},${origen.latitude}'
        ';${destino.longitude},${destino.latitude}';
    final url = Uri.parse(
      '$servidor/route/v1/driving/$coords'
      // `alternatives` porque OSRM ordena por tiempo, y a veces la segunda
      // opción tarda lo mismo y es un kilómetro más corta. Ver [elegirMejor].
      '?overview=full&geometries=geojson&alternatives=3',
    );

    try {
      // Un reintento: el servidor publico corta de vez en cuando, y volver a
      // preguntar sale mas barato que dejar al pasajero con la linea recta.
      var respuesta = await _pedir(url);
      respuesta ??= await _pedir(url);

      if (respuesta == null || respuesta.statusCode != 200) return null;

      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      if (cuerpo['code'] != 'Ok') return null;

      final rutas = cuerpo['routes'] as List?;
      if (rutas == null || rutas.isEmpty) return null;

      return elegirMejor([
        for (final r in rutas.cast<Map<String, dynamic>>())
          Ruta(
            puntos: [
              for (final par
                  in (r['geometry'] as Map<String, dynamic>)['coordinates']
                      as List)
                LatLng(
                  (par[1] as num).toDouble(),
                  (par[0] as num).toDouble(),
                ),
            ],
            metros: (r['distance'] as num).toDouble(),
            duracion: Duration(seconds: (r['duration'] as num).round()),
          ),
      ]);
    } catch (_) {
      // Sin red, con el servidor caído o con una respuesta rara: se devuelve
      // null y la pantalla sigue funcionando.
      return null;
    }
  }

  Future<http.Response?> _pedir(Uri url) async {
    try {
      return await http.get(url).timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
  }

  /// Cuánto más lenta puede ser una ruta para que aún compense por ser corta.
  ///
  /// El 10 % es lo que separa «da igual, van casi iguales» de «esta te deja
  /// tirado en un atasco».
  static const double _margenTiempo = 1.10;

  /// Elige entre las rutas que devuelve OSRM.
  ///
  /// OSRM ordena por **tiempo**, no por distancia, y a veces la segunda opción
  /// tarda lo mismo y es un kilómetro más corta: quedarse siempre con la
  /// primera hace dar rodeos que no aportan nada.
  ///
  /// La regla: de entre las que no tardan más de un [_margenTiempo] sobre la
  /// más rápida, se toma la más corta. Así se prefiere el camino directo sin
  /// aceptar uno mucho más lento por unos metros.
  ///
  /// Pública para poder probarla sin salir a la red.
  static Ruta? elegirMejor(List<Ruta> rutas) {
    if (rutas.isEmpty) return null;

    final masRapida = rutas
        .map((r) => r.duracion.inSeconds)
        .reduce((a, b) => a < b ? a : b);
    final tope = masRapida * _margenTiempo;

    final razonables =
        rutas.where((r) => r.duracion.inSeconds <= tope).toList();

    razonables.sort((a, b) => a.metros.compareTo(b.metros));
    return razonables.first;
  }
}

/// Un recorrido calculado.
class Ruta {
  const Ruta({
    required this.puntos,
    required this.metros,
    required this.duracion,
  });

  /// Vértices del trazado, listos para dibujar.
  final List<LatLng> puntos;

  final double metros;
  final Duration duracion;

  /// Para guardar la ruta en el teléfono. Los puntos van con cinco decimales
  /// —un metro— porque a la escala del mapa nadie distingue más, y a cientos
  /// de puntos por ruta la diferencia de tamaño sí se nota.
  Map<String, dynamic> aJson() => {
        'm': metros,
        's': duracion.inSeconds,
        'p': [
          for (final punto in puntos)
            [
              double.parse(punto.latitude.toStringAsFixed(5)),
              double.parse(punto.longitude.toStringAsFixed(5)),
            ],
        ],
      };

  /// Reconstruye una ruta guardada. Devuelve `null` si el dato no sirve, para
  /// que una caché corrupta no rompa el mapa.
  static Ruta? desdeJson(Map<String, dynamic> json) {
    try {
      final puntos = [
        for (final par in json['p'] as List)
          LatLng((par[0] as num).toDouble(), (par[1] as num).toDouble()),
      ];
      if (puntos.length < 2) return null;
      return Ruta(
        puntos: puntos,
        metros: (json['m'] as num).toDouble(),
        duracion: Duration(seconds: (json['s'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  /// «5,1 km» o «850 m».
  String get distanciaTexto => metros >= 1000
      ? '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${metros.round()} m';

  /// «8 min» o «1 h 5 min».
  String get duracionTexto {
    final minutos = duracion.inMinutes;
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }
}
