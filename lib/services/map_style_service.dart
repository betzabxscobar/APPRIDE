import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';

/// El estilo del mapa, en teselas vectoriales.
///
/// ## Por qué se cambió
///
/// Hasta ahora el mapa usaba las teselas **rasterizadas** de
/// `tile.openstreetmap.org`: imágenes PNG ya dibujadas. Los datos de ese
/// servidor están al día —OpenStreetMap se refresca de forma continua—, pero
/// el dibujo es el estilo clásico de OSM, de hace más de una década: colores
/// apagados, tipografías pequeñas y, en una pantalla de teléfono moderna,
/// visiblemente borroso, porque son imágenes de 256 px que hay que ampliar.
///
/// Una tesela **vectorial** no trae el dibujo, trae los datos; el teléfono la
/// pinta a la resolución de su pantalla. De ahí que se vea nítida a cualquier
/// zoom y que el estilo se pueda cambiar sin cambiar de servidor.
///
/// ## Por qué OpenFreeMap
///
/// **No pide clave, ni cuenta, ni tarjeta, ni tiene cupo.** Es la única
/// condición que importa aquí: cada intento anterior con CARTO, Mapbox o Esri
/// murió en el mismo sitio, pidiendo una clave. Ver `docs/MAPA.md`.
///
/// La atribución sí es obligatoria y la pone [RideMap] en el mapa:
/// «© OpenMapTiles © OpenStreetMap».
///
/// ## Vida de los estilos
///
/// Se cargan una vez y se quedan en memoria mientras viva la app. No se
/// liberan a propósito: el mapa se monta y se desmonta en cada pantalla —
/// inicio, seguimiento, elegir destino— y recargar el estilo en cada una haría
/// parpadear el mapa y repetir la descarga. El paquete además guarda el estilo
/// en disco, así que a partir del segundo arranque abre sin red.
class MapStyleService {
  MapStyleService._();

  static final MapStyleService instance = MapStyleService._();

  /// Estilos de OpenFreeMap. Hay más (`bright`, `positron`, `fiord`); estos
  /// dos son los que combinan con el tema de la app.
  static const String _urlClaro = 'https://tiles.openfreemap.org/styles/liberty';
  static const String _urlOscuro = 'https://tiles.openfreemap.org/styles/dark';

  final Map<bool, Style> _cargados = {};
  final Map<bool, Future<Style?>> _enCurso = {};

  /// Fuerza el respaldo rasterizado y no sale a la red.
  ///
  /// Existe para las pruebas de widgets: ahí no hay red, la carga del estilo
  /// nunca termina y deja un temporizador vivo que hace fallar la prueba con
  /// «pending timers». Poniéndolo en `true` el mapa se comporta exactamente
  /// como cuando OpenFreeMap no responde, que es justo lo que esas pruebas
  /// comprueban.
  bool soloRaster = false;

  /// `true` si algún estilo llegó a cargar. Lo usa el mapa para decidir qué
  /// atribución mostrar.
  bool get hayVectorial => _cargados.isNotEmpty;

  /// El estilo ya cargado, si lo está. Síncrono: sirve para pintar en el
  /// primer frame sin esperar a nada.
  Style? cacheado({required bool oscuro}) =>
      soloRaster ? null : _cargados[oscuro];

  /// Carga el estilo que toca, o lo devuelve si ya estaba.
  ///
  /// Devuelve `null` si falla. **Nunca lanza**: si OpenFreeMap no responde, el
  /// mapa se queda con las teselas de OpenStreetMap de siempre, que siguen
  /// siendo un mapa perfectamente usable. Un mapa feo es mucho mejor que una
  /// pantalla gris.
  Future<Style?> estilo({required bool oscuro}) {
    if (soloRaster) return Future.value(null);

    final listo = _cargados[oscuro];
    if (listo != null) return Future.value(listo);

    // Varias pantallas con mapa pueden pedirlo a la vez al arrancar. Sin esto
    // se descargaría el mismo estilo una vez por pantalla.
    return _enCurso[oscuro] ??= _cargar(oscuro);
  }

  Future<Style?> _cargar(bool oscuro) async {
    try {
      final estilo = await StyleReader(
        uri: oscuro ? _urlOscuro : _urlClaro,
      ).read().timeout(const Duration(seconds: 20));

      _cargados[oscuro] = estilo;
      return estilo;
    } catch (e) {
      // Sin red, servidor caído o estilo con un formato inesperado.
      debugPrint('No se pudo cargar el estilo del mapa: $e');
      return null;
    } finally {
      _enCurso.remove(oscuro);
    }
  }
}
