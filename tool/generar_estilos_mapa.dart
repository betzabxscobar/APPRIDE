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
/// 3. **El oscuro era casi negro.** Su fondo es `rgb(12,12,12)`, y sobre el
///    teléfono se leía como un agujero, no como un mapa.
///
/// Los dos primeros se arreglan igual: se copian las capas de POI de `liberty`
/// al oscuro —recoloreadas— y se baja un nivel el zoom al que aparecen en los
/// dos. Un nivel, no tres: las etiquetas se pisan entre ellas y un mapa
/// ilegible es peor que uno con pocos nombres.
///
/// El tercero lo arregla [_aclarar]: sube la luminosidad de los colores
/// oscuros y les da el azul del tema de la app, para que siga siendo
/// claramente un mapa de noche pero se distingan las calles.
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

  // El aclarado va ANTES de trasplantar: las capas de nombres ya se colorean
  // a mano en [_paraOscuro] y pasarlas otra vez por aquí las apagaría.
  _aclarar(oscuro['layers'] as List);

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

/// Sube el mapa oscuro de «casi negro» a «azul de noche».
///
/// El estilo `dark` de OpenFreeMap es gris puro y muy bajo: su fondo es
/// `rgb(12,12,12)`. En el teléfono no se leía como un mapa nocturno sino como
/// un hueco negro con rayas.
///
/// Se recorren todos los colores y a los **oscuros** se les sube la
/// luminosidad y se les mete el azul del tema de la app. A los claros no se
/// les toca: son los textos, y bajarlos los volvería ilegibles.
void _aclarar(List<dynamic> capas) {
  for (final capa in capas.cast<Map<String, dynamic>>()) {
    for (final clave in const ['paint', 'layout']) {
      final props = capa[clave];
      if (props is Map) {
        // `map` sobre un Map dinamico devuelve Map<dynamic,dynamic>, asi que
        // hay que reconstruir el tipo que espera el JSON de salida.
        capa[clave] = Map<String, dynamic>.from(
          _mapearColores(props) as Map,
        );
      }
    }
  }
}

/// Recorre cualquier valor del estilo cambiando los colores que encuentre.
///
/// Va a ciegas por la estructura a propósito: un color puede estar suelto
/// (`"#111"`) o dentro de una expresión de MapLibre —interpolaciones por zoom,
/// `match`, `case`—, y no compensa entender cada forma para encontrarlos.
Object? _mapearColores(Object? valor) {
  if (valor is String) return _esColor(valor) ? _aclararColor(valor) : valor;
  if (valor is List) return valor.map(_mapearColores).toList();
  if (valor is Map) {
    return valor.map((k, v) => MapEntry(k, _mapearColores(v)));
  }
  return valor;
}

bool _esColor(String v) {
  final t = v.trim();
  return RegExp(r'^#[0-9a-fA-F]{3,8}$').hasMatch(t) ||
      RegExp(r'^(rgb|rgba|hsl|hsla)\s*\(').hasMatch(t);
}

/// El azul del tema oscuro de la app, para que el mapa no desentone.
const double _tonoRide = 205;
const double _saturacionRide = 0.20;

String _aclararColor(String crudo) {
  final rgba = _leerColor(crudo);
  if (rgba == null) return crudo;

  final (r, g, b, a) = rgba;
  final (h, sat, l) = _aHsl(r, g, b);

  // Los claros son los textos: se dejan como están.
  if (l >= 0.5) return crudo;

  // 0.10 de suelo para que el negro puro deje de serlo, y 0.55 de pendiente
  // para no aplastar la diferencia entre el fondo y las calles.
  final nuevaL = 0.10 + 0.55 * l;

  // Solo se tiñen los grises. Si el color ya tenía tono propio —el azul del
  // agua, el verde de un parque— se respeta.
  final tinta = sat < 0.15;
  final (nr, ng, nb) = _aRgb(
    tinta ? _tonoRide : h,
    tinta ? _saturacionRide : sat,
    nuevaL,
  );

  return a >= 1 ? 'rgb($nr,$ng,$nb)' : 'rgba($nr,$ng,$nb,$a)';
}

(int, int, int, double)? _leerColor(String crudo) {
  final t = crudo.trim();

  if (t.startsWith('#')) {
    var hex = t.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6 && hex.length != 8) return null;
    final v = int.tryParse(hex.substring(0, 6), radix: 16);
    if (v == null) return null;
    final a = hex.length == 8
        ? (int.tryParse(hex.substring(6), radix: 16) ?? 255) / 255
        : 1.0;
    return ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff, a);
  }

  final m = RegExp(r'^(rgb|rgba|hsl|hsla)\s*\(([^)]*)\)').firstMatch(t);
  if (m == null) return null;
  final partes = m
      .group(2)!
      .split(',')
      .map((x) => x.trim().replaceAll('%', ''))
      .toList();
  if (partes.length < 3) return null;

  final n = partes.map((x) => double.tryParse(x) ?? 0).toList();
  final a = partes.length > 3 ? n[3] : 1.0;

  if (m.group(1)!.startsWith('hsl')) {
    final (r, g, b) = _aRgb(n[0], n[1] / 100, n[2] / 100);
    return (r, g, b, a);
  }
  return (n[0].round(), n[1].round(), n[2].round(), a);
}

(double, double, double) _aHsl(int r, int g, int b) {
  final rr = r / 255, gg = g / 255, bb = b / 255;
  final max = [rr, gg, bb].reduce((x, y) => x > y ? x : y);
  final min = [rr, gg, bb].reduce((x, y) => x < y ? x : y);
  final l = (max + min) / 2;
  if (max == min) return (0, 0, l);

  final d = max - min;
  final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  double h;
  if (max == rr) {
    h = (gg - bb) / d + (gg < bb ? 6 : 0);
  } else if (max == gg) {
    h = (bb - rr) / d + 2;
  } else {
    h = (rr - gg) / d + 4;
  }
  return (h * 60, s, l);
}

(int, int, int) _aRgb(double h, double s, double l) {
  if (s == 0) {
    final v = (l * 255).round();
    return (v, v, v);
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;

  double canal(double t) {
    var tt = t;
    if (tt < 0) tt += 1;
    if (tt > 1) tt -= 1;
    if (tt < 1 / 6) return p + (q - p) * 6 * tt;
    if (tt < 1 / 2) return q;
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
    return p;
  }

  final hh = (h % 360) / 360;
  return (
    (canal(hh + 1 / 3) * 255).round(),
    (canal(hh) * 255).round(),
    (canal(hh - 1 / 3) * 255).round(),
  );
}

/// La misma capa, con el texto claro sobre un halo oscuro.
///
/// El color del icono no se toca: los del sprite ya son de color y se ven
/// igual de bien sobre fondo oscuro.
Map<String, dynamic> _paraOscuro(Map<String, dynamic> capa) {
  final copia = jsonDecode(jsonEncode(capa)) as Map<String, dynamic>;
  final paint = Map<String, dynamic>.from(copia['paint'] as Map? ?? {});

  paint['text-color'] = '#c8d3de';
  // El halo va a juego con el fondo ya aclarado, no negro puro: un halo mas
  // oscuro que el mapa recorta las letras como pegatinas.
  paint['text-halo-color'] = '#111a21';
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
