import 'dart:convert';
import 'dart:io';

/// Genera los dos estilos de mapa que usa la app, a partir de los de
/// OpenFreeMap.
///
/// ```sh
/// dart run tool/generar_estilos_mapa.dart
/// ```
///
/// ## Por qué no se usan los de OpenFreeMap tal cual
///
/// Dos problemas, encontrados probando el APK en Quito:
///
/// 1. **El estilo oscuro no tiene ni un nombre de lugar.** `dark` y `positron`
///    son mapas base minimalistas: cero capas de POI. Usarlos dejaba el modo
///    oscuro sin farmacias, sin restaurantes y sin paradas — un plano de
///    calles y nada más.
/// 2. **En claro los nombres aparecen tarde.** `liberty` los suelta por rango:
///    los importantes en z15, el resto en z16 y z17. A la altura a la que se
///    mira un mapa de viajes se ven cuatro etiquetas contadas.
///
/// Los dos se arreglan igual: se copian las capas de POI de `liberty` al
/// oscuro —recoloreadas— y se baja un nivel el zoom al que aparecen en los
/// dos. Un nivel, no tres: las etiquetas se pisan entre ellas y un mapa
/// ilegible es peor que uno con pocos nombres.
///
/// Los dos estilos comparten iconos (`sprite`), fuentes (`glyphs`) y origen de
/// teselas, así que el trasplante no arrastra nada más.
///
/// ## Lo que esto cuesta
///
/// Los estilos quedan **congelados** en el momento de generarlos: si
/// OpenFreeMap mejora los suyos, aquí no llega hasta volver a ejecutar esto.
/// Las teselas no se congelan —esas siguen viniendo de su servidor y se
/// actualizan solas—, solo el cómo se dibujan.
Future<void> main() async {
  const base = 'https://tiles.openfreemap.org/styles';
  final salida = Directory('assets/mapa')..createSync(recursive: true);

  final claro = await _bajar('$base/liberty');
  final oscuro = await _bajar('$base/dark');

  // Las capas de nombres de sitios. En el oscuro no existen: hay que llevarlas.
  //
  // Se copian **antes** de tocar el estilo claro. Si se cogieran después serían
  // referencias a unas capas ya rebajadas, y al rebajar luego el oscuro
  // bajarían dos niveles en vez de uno: `poi_r1` acabaría en z13, donde las
  // etiquetas se amontonan hasta tapar las calles.
  final poi = (claro['layers'] as List)
      .cast<Map<String, dynamic>>()
      .where((l) => l['source-layer'] == 'poi' && l['type'] == 'symbol')
      .map((l) => jsonDecode(jsonEncode(l)) as Map<String, dynamic>)
      .toList();

  if (poi.isEmpty) {
    stderr.writeln('El estilo claro ya no trae capas de POI: revisa el cambio '
        'antes de generar nada.');
    exitCode = 1;
    return;
  }

  _adelantar(claro['layers'] as List);
  _escribir('${salida.path}/claro.json', claro);

  // Copia recoloreada para fondo oscuro, encima de todo lo demás.
  (oscuro['layers'] as List).addAll(poi.map(_paraOscuro));
  _adelantar(oscuro['layers'] as List);
  _escribir('${salida.path}/oscuro.json', oscuro);

  stdout.writeln('Listo. ${poi.length} capas de nombres en el oscuro.');
}

/// Baja un nivel el zoom al que aparece cada capa de nombres.
void _adelantar(List<dynamic> capas) {
  for (final capa in capas.cast<Map<String, dynamic>>()) {
    if (capa['type'] != 'symbol') continue;
    final fuente = capa['source-layer'];
    if (fuente != 'poi' && fuente != 'transportation_name') continue;

    final minimo = capa['minzoom'];
    // Por debajo de z12 no se baja: a esa escala se ve media ciudad y las
    // etiquetas se amontonan hasta tapar las calles.
    if (minimo is num && minimo > 12) capa['minzoom'] = minimo - 1;
  }
}

/// La misma capa, con el texto claro sobre un halo oscuro.
///
/// El color del icono no se toca: los del sprite ya son de color y se ven
/// igual de bien sobre fondo oscuro.
Map<String, dynamic> _paraOscuro(Map<String, dynamic> capa) {
  final copia = jsonDecode(jsonEncode(capa)) as Map<String, dynamic>;
  final paint = Map<String, dynamic>.from(copia['paint'] as Map? ?? {});

  paint['text-color'] = '#c8d3de';
  paint['text-halo-color'] = '#0b0b0b';
  paint['text-halo-width'] = 1.4;
  paint['text-halo-blur'] = 0.4;

  copia['paint'] = paint;
  return copia;
}

Future<Map<String, dynamic>> _bajar(String url) async {
  final cliente = HttpClient();
  try {
    final respuesta = await (await cliente.getUrl(Uri.parse(url))).close();
    if (respuesta.statusCode != 200) {
      throw HttpException('$url respondió ${respuesta.statusCode}');
    }
    final cuerpo = await respuesta.transform(utf8.decoder).join();
    return jsonDecode(cuerpo) as Map<String, dynamic>;
  } finally {
    cliente.close();
  }
}

void _escribir(String ruta, Map<String, dynamic> estilo) {
  File(ruta).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(estilo));
  final kb = (File(ruta).lengthSync() / 1024).toStringAsFixed(0);
  stdout.writeln('  $ruta  ($kb KB)');
}
