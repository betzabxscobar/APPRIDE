// Es una herramienta de linea de comandos: aqui `print` es la salida.
// ignore_for_file: avoid_print

// Compara el buscador actual (Photon, sobre OpenStreetMap) con TomTom.
//
//   dart run tool/comparar_buscador.dart TU_CLAVE "Alma Lojana" "otro sitio"
//
// Sin clave solo enseña lo que devuelve Photon, que sirve igual para ver que
// tan mal esta encontrando las cosas.
//
// Las busquedas van sesgadas a Quito, que es donde se usa la app.
import 'dart:convert';
import 'dart:io';

const _lat = -0.1807;
const _lng = -78.4678;

const _porDefecto = [
  'Alma Lojana',
  'Urbanizacion Alma Lojana Baja',
  'La Carolina',
  'Universidad Central del Ecuador',
];

Future<List<String>> _photon(HttpClient cliente, String q) async {
  final url = Uri.https('photon.komoot.io', '/api/', {
    'q': q,
    'limit': '4',
    'lat': '$_lat',
    'lon': '$_lng',
  });

  try {
    final p = await cliente.getUrl(url);
    p.headers.set('User-Agent', 'RideApp/1.0 (proyecto academico)');
    final r = await p.close();
    if (r.statusCode != 200) return ['(HTTP ${r.statusCode})'];

    final cuerpo = jsonDecode(await r.transform(utf8.decoder).join())
        as Map<String, dynamic>;
    final rasgos = cuerpo['features'] as List? ?? const [];

    return [
      for (final f in rasgos.cast<Map<String, dynamic>>())
        _linea(
          (f['properties'] as Map<String, dynamic>?) ?? const {},
          ['name', 'street'],
          ['district', 'city', 'state', 'country'],
        ),
    ];
  } catch (e) {
    return ['(error: $e)'];
  }
}

Future<List<String>> _tomtom(HttpClient cliente, String clave, String q) async {
  final url = Uri.https(
    'api.tomtom.com',
    '/search/2/search/${Uri.encodeComponent(q)}.json',
    {
      'key': clave,
      'limit': '4',
      'language': 'es-ES',
      'typeahead': 'true',
      'lat': '$_lat',
      'lon': '$_lng',
    },
  );

  try {
    final r = await (await cliente.getUrl(url)).close();
    final texto = await r.transform(utf8.decoder).join();
    if (r.statusCode != 200) {
      return ['(HTTP ${r.statusCode}) ${texto.trim()}'];
    }

    final resultados =
        (jsonDecode(texto) as Map<String, dynamic>)['results'] as List? ??
            const [];

    return [
      for (final x in resultados.cast<Map<String, dynamic>>())
        [
          (x['poi'] as Map<String, dynamic>?)?['name'] as String? ??
              (x['address'] as Map<String, dynamic>?)?['streetName'] as String? ??
              '?',
          (x['address'] as Map<String, dynamic>?)?['freeformAddress'] as String? ??
              '',
        ].where((e) => e.isNotEmpty).join('  —  '),
    ];
  } catch (e) {
    return ['(error: $e)'];
  }
}

String _linea(
  Map<String, dynamic> p,
  List<String> claveNombre,
  List<String> claveContexto,
) {
  final nombre = claveNombre
          .map((k) => p[k] as String?)
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null) ??
      '?';
  final contexto = claveContexto
      .map((k) => p[k] as String?)
      .whereType<String>()
      .where((e) => e.isNotEmpty)
      .join(', ');
  return contexto.isEmpty ? nombre : '$nombre  —  $contexto';
}

Future<void> main(List<String> args) async {
  final clave = args.isNotEmpty && args.first.length >= 20 ? args.first : null;
  final consultas = args.length > (clave == null ? 0 : 1)
      ? args.skip(clave == null ? 0 : 1).toList()
      : _porDefecto;

  if (clave == null) {
    print('Sin clave de TomTom: solo se consulta Photon.');
    print('Para comparar: dart run tool/comparar_buscador.dart TU_CLAVE\n');
  }

  final cliente = HttpClient();

  for (final q in consultas) {
    print('═' * 68);
    print('  $q');
    print('═' * 68);

    print('\nPhoton (OpenStreetMap, lo que usa la app hoy):');
    final a = await _photon(cliente, q);
    if (a.isEmpty) {
      print('   — sin resultados —');
    } else {
      for (final l in a) {
        print('   $l');
      }
    }

    if (clave != null) {
      print('\nTomTom:');
      final b = await _tomtom(cliente, clave, q);
      if (b.isEmpty) {
        print('   — sin resultados —');
      } else {
        for (final l in b) {
          print('   $l');
        }
      }
    }
    print('');
  }

  cliente.close();

  if (clave != null) {
    print('Si TomTom encuentra lo que Photon no, compila con:');
    print('  flutter build apk --release --dart-define=TOMTOM_KEY=$clave');
  }
}
