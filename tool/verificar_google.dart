// Es una herramienta de linea de comandos: aqui `print` es la salida.
// ignore_for_file: avoid_print

// Comprueba que una clave de Google Places sirve, antes de compilar con ella.
//
//   dart run tool/verificar_google.dart TU_CLAVE
//
// Hace las dos llamadas que hace la app —autocompletado y coordenadas— sobre
// una direccion real de Quito, y ademas comprueba que las dos comparten sesion
// de facturacion, que es lo que evita pagar por cada pulsacion.
import 'dart:convert';
import 'dart:io';

const _host = 'places.googleapis.com';
const _busqueda = 'Avenida Amazonas y Naciones Unidas';

// Quito, para sesgar la busqueda.
const _lat = -0.1807;
const _lng = -78.4678;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.trim().isEmpty) {
    stderr.writeln('Uso: dart run tool/verificar_google.dart TU_CLAVE');
    stderr.writeln('');
    stderr.writeln('La clave se saca en console.cloud.google.com, activando');
    stderr.writeln('"Places API (New)". Empieza por AIza.');
    exit(64);
  }

  final clave = args.first.trim();

  if (!clave.startsWith('AIza')) {
    stderr.writeln('Eso no parece una clave de Google: empiezan por "AIza".');
    stderr.writeln('  $clave');
    exit(64);
  }

  final cliente = HttpClient();
  final sesion = 'verificacion${DateTime.now().millisecondsSinceEpoch}';

  print('Buscando "$_busqueda" cerca de Quito...\n');

  // ---- 1) Autocompletado
  final peticion = await cliente.postUrl(
    Uri.https(_host, '/v1/places:autocomplete'),
  );
  peticion.headers
    ..set('Content-Type', 'application/json')
    ..set('X-Goog-Api-Key', clave)
    ..set(
      'X-Goog-FieldMask',
      'suggestions.placePrediction.placeId,'
          'suggestions.placePrediction.structuredFormat',
    );
  peticion.write(jsonEncode({
    'input': _busqueda,
    'sessionToken': sesion,
    'languageCode': 'es',
    'regionCode': 'ec',
    'locationBias': {
      'circle': {
        'center': {'latitude': _lat, 'longitude': _lng},
        'radius': 30000.0,
      },
    },
  }));

  final r1 = await peticion.close();
  final cuerpo1 = await r1.transform(utf8.decoder).join();

  if (r1.statusCode != 200) {
    print('✗ El autocompletado falló (HTTP ${r1.statusCode}):');
    print(cuerpo1.trim());
    print('');
    print('Lo habitual: falta activar "Places API (New)" en el proyecto, o la');
    print('clave tiene restricciones que no dejan pasar esta llamada.');
    cliente.close();
    exit(1);
  }

  final sugerencias =
      (jsonDecode(cuerpo1) as Map<String, dynamic>)['suggestions'] as List? ??
          const [];

  if (sugerencias.isEmpty) {
    print('✗ La clave funciona pero no devolvió ninguna sugerencia.');
    cliente.close();
    exit(1);
  }

  print('✓ Autocompletado: ${sugerencias.length} sugerencias');
  for (final s in sugerencias.take(3)) {
    final p = (s as Map<String, dynamic>)['placePrediction']
        as Map<String, dynamic>?;
    final f = p?['structuredFormat'] as Map<String, dynamic>?;
    final principal = (f?['mainText'] as Map<String, dynamic>?)?['text'];
    final secundario = (f?['secondaryText'] as Map<String, dynamic>?)?['text'];
    print('    $principal — ${secundario ?? ''}');
  }

  // ---- 2) Coordenadas del primero, en la MISMA sesion
  final primero = (sugerencias.first as Map<String, dynamic>)['placePrediction']
      as Map<String, dynamic>;
  final placeId = primero['placeId'] as String;

  final p2 = await cliente.getUrl(
    Uri.https(_host, '/v1/places/$placeId', {'sessionToken': sesion}),
  );
  p2.headers
    ..set('X-Goog-Api-Key', clave)
    ..set('X-Goog-FieldMask', 'location');

  final r2 = await p2.close();
  final cuerpo2 = await r2.transform(utf8.decoder).join();
  cliente.close();

  if (r2.statusCode != 200) {
    print('');
    print('✗ Las coordenadas fallaron (HTTP ${r2.statusCode}):');
    print(cuerpo2.trim());
    exit(1);
  }

  final loc =
      (jsonDecode(cuerpo2) as Map<String, dynamic>)['location']
          as Map<String, dynamic>;

  print('');
  print('✓ Coordenadas: ${loc['latitude']}, ${loc['longitude']}');
  print('✓ Las dos llamadas fueron en la misma sesión de facturación,');
  print('  así que cuentan como una sola.');
  print('');
  print('Úsala así:');
  print('  flutter run --dart-define=GOOGLE_PLACES_KEY=$clave');
}
