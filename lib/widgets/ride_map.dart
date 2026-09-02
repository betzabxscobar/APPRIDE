import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    show Style, VectorTileLayer;
// Solo LatLng: latlong2 exporta tambien una clase Path que taparia la de
// Flutter y rompe cualquier CustomPainter de este archivo.
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../services/map_style_service.dart';

/// Mapa base de Ride.
///
/// Teselas **vectoriales** de OpenFreeMap y rutas de OSRM. **Sin claves, sin
/// cuentas y sin cuotas**: es lo que hace que la app funcione recién clonada,
/// sin configuración previa.
///
/// Antes eran teselas rasterizadas de OpenStreetMap —imágenes ya dibujadas—.
/// Los datos estaban al día, pero el dibujo era el estilo clásico de OSM y en
/// una pantalla de teléfono se veía borroso, porque hay que ampliar imágenes
/// de 256 px. Lo vectorial lo pinta el propio teléfono a su resolución. Ver
/// [MapStyleService].
///
/// Las de OpenStreetMap **siguen ahí como respaldo**: es lo que se ve mientras
/// baja el estilo, y lo que queda si OpenFreeMap no responde. Un mapa con el
/// estilo viejo es mucho mejor que un hueco gris.
///
/// En ese respaldo, y solo en él, el modo oscuro invierte las teselas claras
/// con el filtro de `flutter_map`, porque OSM no publica un estilo oscuro.
/// OpenFreeMap sí lo tiene, así que en vectorial no hace falta el truco.
///
/// Se probaron proveedores más bonitos —CARTO, Mapbox, Esri— y todos exigen
/// clave, cuenta o las tres cosas. La comparación completa, con lo que costó
/// cada uno, está en `docs/MAPA.md`.
///
/// La atribución es obligatoria: la licencia ODbL de OpenStreetMap la exige
/// allí donde se muestren los datos, y OpenMapTiles —el esquema de las teselas
/// de OpenFreeMap— también.
class RideMap extends StatelessWidget {
  const RideMap({
    super.key,
    required this.centro,
    this.zoom = 15,
    this.marcadores = const [],
    this.rutas = const [],
    this.controlador,
    this.onTap,
    this.interactivo = true,
    this.margenCredito = EdgeInsets.zero,
    this.onListo,
    this.miUbicacion,
  });

  final LatLng centro;
  final double zoom;
  final List<MapMarker> marcadores;

  /// Trazados a dibujar, en orden: el último queda encima.
  ///
  /// Son varios y no uno porque un viaje asignado tiene **dos** tramos que hay
  /// que ver a la vez: el que hace el chofer para llegar a recoger y el del
  /// viaje en sí. Ver [MapRoute].
  ///
  /// El mapa solo los pinta. Quién los calcula y cuándo se recalculan es
  /// asunto de la pantalla: antes esto pedía la ruta a OSRM por su cuenta, y
  /// con dos tramos habría acabado pidiendo lo que ya tenía la pantalla.
  final List<MapRoute> rutas;

  final MapController? controlador;
  final void Function(LatLng punto)? onTap;
  final bool interactivo;

  /// Separación del crédito a OpenStreetMap respecto al borde del mapa.
  ///
  /// En las pantallas donde una hoja tapa la parte de abajo hay que subirlo:
  /// la licencia ODbL obliga a que la atribución se vea, y detrás de una hoja
  /// no se ve.
  final EdgeInsets margenCredito;

  /// Aviso de que el mapa ya está montado.
  ///
  /// `centro` solo se aplica al construir: para mover la vista después —al
  /// llegar la posición del GPS, por ejemplo— hay que usar [controlador], y
  /// llamarlo antes de este aviso lanza excepción.
  final VoidCallback? onListo;

  /// Dónde está quien mira el mapa, con su margen de error en metros.
  ///
  /// Se dibuja como el punto azul de siempre, no como un alfiler: un alfiler
  /// dice «este sitio», el punto dice «tú». El halo es el margen real, así que
  /// cuando la posición viene de la IP se ve enorme y queda claro que no hay
  /// que fiarse.
  final ({LatLng punto, double precision})? miUbicacion;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controlador,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: zoom,
        // Topes del gesto de zoom. Por encima de 21 la tesela de z19 se ve tan
        // ampliada que ya no aporta nada, y por debajo de 3 el mundo cabe
        // varias veces en la pantalla y se repite.
        maxZoom: 21,
        minZoom: 3,
        // Lo que se ve mientras bajan las teselas. En blanco, el modo oscuro
        // arrancaba con un destello claro en toda la pantalla.
        backgroundColor: context.ride.surfaceSunken,
        onMapReady: onListo,
        onTap: onTap == null ? null : (_, punto) => onTap!(punto),
        interactionOptions: InteractionOptions(
          flags: interactivo
              ? InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom
              // Sin rotación: en un mapa de viajes desorienta más de lo que
              // aporta, y deja los marcadores torcidos.
              : InteractiveFlag.none,
        ),
      ),
      children: [
        _CapaBase(oscuro: context.ride.isDark),
        if (rutas.any((r) => r.puntos.length >= 2))
          PolylineLayer(
            polylines: [
              for (final r in rutas)
                if (r.puntos.length >= 2)
                  Polyline(
                    points: r.puntos,
                    strokeWidth: r.grosor,
                    color: r.color,
                    // Sin `const`: el assert de StrokePattern.dashed mira el
                    // largo de la lista y eso no se puede evaluar en tiempo de
                    // compilacion.
                    pattern: r.discontinua
                        ? StrokePattern.dashed(segments: const [14, 9])
                        : const StrokePattern.solid(),
                    // El borde blanco es lo que hace que la línea se lea sobre
                    // un parque verde o una avenida clara.
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.white.withValues(alpha: 0.7),
                  ),
            ],
          ),
        if (miUbicacion != null) ...[
          CircleLayer(
            circles: [
              CircleMarker(
                point: miUbicacion!.punto,
                // Un margen de 3 m no se vería; se le pone un mínimo para que
                // el halo siempre exista.
                radius: miUbicacion!.precision.clamp(12, 4000),
                useRadiusInMeter: true,
                color: AppColors.primary.withValues(alpha: 0.16),
                borderColor: AppColors.primary.withValues(alpha: 0.35),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: miUbicacion!.punto,
                width: 26,
                height: 26,
                child: const _PuntoAzul(),
              ),
            ],
          ),
        ],
        if (marcadores.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final m in marcadores)
                Marker(
                  point: m.punto,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: _Pin(color: m.color, icono: m.icono),
                ),
            ],
          ),
        _CreditoOSM(margen: margenCredito),
      ],
    );
  }
}

/// El fondo del mapa: vectorial si se pudo, rasterizado si no.
///
/// Empieza siempre por el respaldo rasterizado, que se pinta en el primer
/// frame sin esperar a nadie, y cambia al vectorial en cuanto el estilo está
/// listo. Así el mapa nunca aparece vacío mientras se descarga el estilo, que
/// la primera vez son unos 40 KB más las fuentes.
class _CapaBase extends StatefulWidget {
  const _CapaBase({required this.oscuro});

  final bool oscuro;

  @override
  State<_CapaBase> createState() => _CapaBaseState();
}

class _CapaBaseState extends State<_CapaBase> {
  static const String _urlTeselas =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  Style? _estilo;

  /// A qué tema pertenece [_estilo].
  ///
  /// Esta pareja es la que arregla el mapa del tema contrario, y va junta a
  /// propósito. Antes se guardaba solo el estilo y se confiaba en
  /// `didUpdateWidget` para cambiarlo al vuelo; bastaba que esa comparación no
  /// llegara a correr —o que llegara tarde— para acabar pintando el mapa de
  /// noche con la app de día. Ahora no hace falta confiar en nada: si el tema
  /// del estilo no es el de ahora, [build] no lo pinta y punto.
  bool? _estiloOscuro;

  /// El estilo que se puede pintar **ahora**, o `null` si el que hay guardado
  /// es del otro tema.
  Style? get _estiloVigente =>
      _estiloOscuro == widget.oscuro ? _estilo : null;

  @override
  void initState() {
    super.initState();
    _tomarDeCache();
    _cargar();
  }

  @override
  void didUpdateWidget(_CapaBase anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.oscuro != widget.oscuro) {
      _tomarDeCache();
      _cargar();
    }
  }

  /// Si otra pantalla ya cargó este estilo, se pinta desde el primer frame.
  void _tomarDeCache() {
    final listo = MapStyleService.instance.cacheado(oscuro: widget.oscuro);
    if (listo == null) return;
    _estilo = listo;
    _estiloOscuro = widget.oscuro;
  }

  Future<void> _cargar() async {
    if (_estiloVigente != null) return;

    final oscuro = widget.oscuro;
    final estilo = await MapStyleService.instance.estilo(oscuro: oscuro);
    // El tema pudo cambiar mientras cargaba: ese estilo ya no sirve.
    if (!mounted || oscuro != widget.oscuro || estilo == null) return;

    setState(() {
      _estilo = estilo;
      _estiloOscuro = oscuro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final estilo = _estiloVigente;
    if (estilo != null) {
      return VectorTileLayer(
        // Una clave por tema: al cambiar, Flutter reemplaza el elemento en vez
        // de reutilizarlo. `VectorTileLayer` guarda el tema ya compilado en su
        // estado y no lo rehace, así que sin la clave seguiría pintando el
        // anterior.
        key: ValueKey(widget.oscuro),
        theme: estilo.theme,
        tileProviders: estilo.providers,
        rasterSources: estilo.rasterSources,
        sprites: estilo.sprites,
      );
    }

    // Mientras carga el estilo que toca. Nunca se pinta el del otro tema: un
    // mapa de noche bajo una app de día se lee como una app rota.
    return TileLayer(
      urlTemplate: _urlTeselas,
      userAgentPackageName: 'com.example.ride',
      // `maxNativeZoom` (19 por defecto) es el tope de lo que sirve OSM: a
      // partir de ahí flutter_map reutiliza la tesela de z19 y la escala.
      //
      // `maxZoom` NO se toca: es hasta dónde se *dibuja* la capa, y su valor
      // por defecto es infinito justamente para que siempre haya teselas.
      // Ponerlo en 19 dejaba el mapa en negro al acercarse más.
      maxNativeZoom: 19,
      // OSM no publica estilo oscuro, así que aquí se invierten sus teselas
      // claras con el filtro de flutter_map. El estilo vectorial oscuro no lo
      // necesita: nace oscuro.
      tileBuilder: widget.oscuro ? darkModeTileBuilder : null,
    );
  }
}

/// Un punto señalado en el mapa.
class MapMarker {
  const MapMarker({
    required this.punto,
    required this.color,
    required this.icono,
  });

  final LatLng punto;
  final Color color;
  final IconData icono;

  factory MapMarker.origen(LatLng punto) =>
      MapMarker(punto: punto, color: AppColors.primary, icono: Icons.my_location);

  factory MapMarker.destino(LatLng punto) =>
      MapMarker(punto: punto, color: AppColors.green, icono: Icons.place);

  factory MapMarker.chofer(LatLng punto) => MapMarker(
        punto: punto,
        color: AppColors.purple,
        icono: Icons.local_taxi,
      );
}

/// Un trazado sobre el mapa.
///
/// Hay dos, y distinguirlos importa: mientras el chofer va de camino, en la
/// pantalla se ven a la vez el trecho que le falta para llegar a recoger y el
/// viaje que vendrá después. Si los dos fueran una línea azul continua no se
/// sabría dónde acaba uno y empieza el otro.
class MapRoute {
  const MapRoute({
    required this.puntos,
    required this.color,
    this.grosor = 5,
    this.discontinua = false,
  });

  /// Vértices del trazado. Con menos de dos no se dibuja nada.
  final List<LatLng> puntos;

  final Color color;
  final double grosor;

  /// A rayas. Se usa para lo que todavía no ha pasado.
  final bool discontinua;

  /// El viaje: del punto de recogida al destino. Azul y continuo, es el
  /// trazado principal.
  factory MapRoute.viaje(List<LatLng> puntos) =>
      MapRoute(puntos: puntos, color: AppColors.primary);

  /// El camino del chofer hasta el punto de recogida. A rayas y en morado —el
  /// mismo color que su alfiler— porque es un tramo previo, no el viaje.
  factory MapRoute.recogida(List<LatLng> puntos) => MapRoute(
        puntos: puntos,
        color: AppColors.purple,
        grosor: 4.5,
        discontinua: true,
      );
}

/// El punto azul de "estoy aquí".
class _PuntoAzul extends StatelessWidget {
  const _PuntoAzul();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icono});

  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Column(
      // La punta del alfiler tiene que quedar en el borde inferior de la caja,
      // porque `alignment: topCenter` sitúa toda la caja encima del punto. Sin
      // esto el alfiler senala unos pixeles mas arriba de donde toca.
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icono, size: 16, color: Colors.white),
        ),
        // Punta que apunta a la coordenada exacta.
        Transform.translate(
          offset: const Offset(0, -3),
          child: CustomPaint(
            size: const Size(10, 8),
            painter: _PuntaPin(color),
          ),
        ),
      ],
    );
  }
}

class _PuntaPin extends CustomPainter {
  const _PuntaPin(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PuntaPin old) => old.color != color;
}

/// Atribución a OpenStreetMap y a OpenMapTiles.
///
/// No es decorativa y no se puede quitar: la licencia ODbL obliga a acreditar
/// la fuente de los datos allí donde se muestren, y OpenFreeMap exige
/// acreditar también el esquema de sus teselas.
///
/// Cambia con la capa que se esté viendo: sobre el respaldo rasterizado solo
/// hay datos de OpenStreetMap, y acreditar a OpenMapTiles ahí sería acreditar
/// a quien no ha puesto nada.
class _CreditoOSM extends StatelessWidget {
  const _CreditoOSM({required this.margen});

  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: margen + const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ride.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          MapStyleService.instance.hayVectorial
              ? '© OpenMapTiles © OpenStreetMap'
              : '© OpenStreetMap',
          style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
        ),
      ),
    );
  }
}
