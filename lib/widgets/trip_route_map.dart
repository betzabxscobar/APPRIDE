import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'
    show CameraFit, LatLngBounds, MapController;
// Distance calcula metros entre dos puntos. No se importa `Path`, que latlong2
// también exporta y taparía la de Flutter.
import 'package:latlong2/latlong.dart' show Distance, LatLng, LengthUnit;

import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../models/trip.dart';
import '../services/routing_service.dart';
import 'ride_map.dart';

/// El mapa del viaje, con los dos recorridos que lo componen.
///
/// Un viaje asignado tiene dos tramos y hasta ahora solo se veía uno:
///
/// 1. **La recogida**: por dónde va el chofer para llegar al punto de partida.
///    A rayas y en morado, porque todavía no ha pasado. Desaparece en cuanto
///    el viaje arranca.
/// 2. **El viaje**: del punto de partida al destino. Azul y continuo.
///
/// Lo usan las dos partes con el mismo código —el pasajero en su seguimiento y
/// el chofer en su viaje activo—, así que los dos ven exactamente lo mismo. La
/// única diferencia es de dónde sale la posición del chofer: él la lee de su
/// propio GPS y el pasajero la recibe por `public.ubicaciones`.
///
/// ## Por qué pinta antes de tener datos
///
/// La ruta del viaje se pide primero a la caché en disco de [RoutingService],
/// de forma síncrona, y solo después a OSRM. Así, al reabrir la app con un
/// viaje en marcha, el recorrido está en el primer frame en vez de aparecer
/// unos segundos más tarde.
class TripRouteMap extends StatefulWidget {
  const TripRouteMap({
    super.key,
    required this.viaje,
    this.chofer,
    this.alto = 220,
    this.onTocar,
  });

  final Trip viaje;

  /// Dónde está el chofer ahora mismo, si se sabe.
  final LatLng? chofer;

  final double alto;

  /// Qué hacer al tocar el mapa. Se usa para abrirlo a pantalla completa.
  final VoidCallback? onTocar;

  @override
  State<TripRouteMap> createState() => _TripRouteMapState();
}

class _TripRouteMapState extends State<TripRouteMap> {
  final MapController _mapa = MapController();
  bool _mapaListo = false;

  Ruta? _viaje;
  Ruta? _recogida;

  /// Con qué origen y destino se pidió [_viaje]. Estas pantallas se
  /// reconstruyen con cada aviso de Realtime y el trayecto no cambia por eso.
  String? _claveViaje;

  /// Desde dónde se calculó [_recogida], para no volver a pedirla mientras el
  /// chofer esté prácticamente en el mismo sitio.
  LatLng? _origenRecogida;

  /// Cuánto se tiene que mover el chofer para recalcular su tramo.
  ///
  /// Por debajo de esto el trazado cambiaría en unos pocos píxeles y no
  /// compensa una llamada a OSRM: el GPS solo ya oscila esa cantidad estando
  /// quieto.
  static const double _metrosParaRecalcular = 60;

  static const Distance _distancia = Distance();

  LatLng? get _origen => widget.viaje.origenLat == null ||
          widget.viaje.origenLng == null
      ? null
      : LatLng(widget.viaje.origenLat!, widget.viaje.origenLng!);

  LatLng? get _destino => widget.viaje.destinoLat == null ||
          widget.viaje.destinoLng == null
      ? null
      : LatLng(widget.viaje.destinoLat!, widget.viaje.destinoLng!);

  /// El tramo de recogida solo tiene sentido antes de subir al auto. Una vez
  /// EN_CURSO, el chofer ya no va hacia el origen: va hacia el destino.
  bool get _mostrarRecogida => switch (widget.viaje.status) {
        TripStatus.aceptado ||
        TripStatus.conductorEnCamino ||
        TripStatus.conductorEnOrigen =>
          widget.chofer != null && _origen != null,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _sembrarDesdeCache();
    _calcularViaje();
    _calcularRecogida();
  }

  @override
  void didUpdateWidget(TripRouteMap anterior) {
    super.didUpdateWidget(anterior);
    _calcularViaje();
    _calcularRecogida();
  }

  /// Lo que ya estaba calculado de una sesión anterior, sin salir a la red.
  void _sembrarDesdeCache() {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null) return;
    _viaje = RoutingService.instance.enCache(origen, destino);
  }

  Future<void> _calcularViaje() async {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null) return;

    final clave = '${origen.latitude},${origen.longitude};'
        '${destino.latitude},${destino.longitude}';
    if (clave == _claveViaje) return;
    _claveViaje = clave;

    final ruta = await RoutingService.instance.entre(origen, destino);
    if (!mounted || ruta == null) return;
    setState(() => _viaje = ruta);
    _encuadrar();
  }

  Future<void> _calcularRecogida() async {
    if (!_mostrarRecogida) {
      if (_recogida != null || _origenRecogida != null) {
        _origenRecogida = null;
        if (mounted) setState(() => _recogida = null);
      }
      return;
    }

    final desde = widget.chofer!;
    final anterior = _origenRecogida;
    if (anterior != null &&
        _distancia.as(LengthUnit.Meter, anterior, desde) <
            _metrosParaRecalcular) {
      return;
    }
    _origenRecogida = desde;

    // `recordar: false`: el origen se mueve con el chofer, así que guardar
    // esta ruta llenaría la caché de trazados de un solo uso.
    final ruta = await RoutingService.instance.entre(
      desde,
      _origen!,
      recordar: false,
    );
    if (!mounted) return;
    // Si el chofer siguió moviéndose mientras OSRM respondía, esta ruta ya no
    // es la buena: la que valga llegará en la siguiente vuelta.
    if (_origenRecogida != desde) return;
    setState(() => _recogida = ruta);
    _encuadrar();
  }

  /// Encaja en pantalla todo lo que hay que ver: los dos extremos del viaje y,
  /// si va en camino, también el chofer.
  ///
  /// Centrar en un punto y fijar un zoom dejaba fuera la mitad del recorrido en
  /// cuanto el viaje era algo más largo que unas cuadras.
  void _encuadrar() {
    if (!_mapaListo) return;

    final puntos = <LatLng>[
      ?_origen,
      ?_destino,
      ?widget.chofer,
      ...?_recogida?.puntos,
      ...?_viaje?.puntos,
    ];
    if (puntos.length < 2) return;

    _mapa.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(puntos),
        // Sitio para que los alfileres no queden pegados al borde ni debajo
        // de la píldora de arriba.
        padding: const EdgeInsets.fromLTRB(38, 54, 38, 38),
        maxZoom: 16.5,
      ),
    );
  }

  /// Lo que se dibuja cuando OSRM no contestó: la recta entre los extremos.
  /// No es el camino real, pero orienta, que es mejor que un mapa vacío.
  List<LatLng> _oRecta(Ruta? ruta, LatLng? a, LatLng? b) {
    if (ruta != null) return ruta.puntos;
    if (a == null || b == null) return const [];
    return [a, b];
  }

  @override
  Widget build(BuildContext context) {
    final origen = _origen;
    final destino = _destino;
    final chofer = widget.chofer;

    // Un viaje sin coordenadas no tiene mapa que enseñar; el resto de la
    // pantalla sirve igual.
    if (origen == null && destino == null) return const SizedBox.shrink();

    final rutas = <MapRoute>[
      MapRoute.viaje(_oRecta(_viaje, origen, destino)),
      if (_mostrarRecogida)
        MapRoute.recogida(_oRecta(_recogida, chofer, origen)),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: SizedBox(
        height: widget.alto,
        child: Stack(
          children: [
            Positioned.fill(
              child: RideMap(
                controlador: _mapa,
                centro: chofer ?? origen ?? destino!,
                zoom: 14,
                interactivo: widget.onTocar == null,
                onTap: widget.onTocar == null ? null : (_) => widget.onTocar!(),
                marcadores: [
                  if (origen != null) MapMarker.origen(origen),
                  if (destino != null) MapMarker.destino(destino),
                  if (chofer != null) MapMarker.chofer(chofer),
                ],
                rutas: rutas,
                onListo: () {
                  _mapaListo = true;
                  _encuadrar();
                },
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              right: 10,
              child: _Pildora(
                viaje: widget.viaje,
                recogida: _recogida,
                recorrido: _viaje,
                mostrandoRecogida: _mostrarRecogida,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resumen de lo que se está viendo, encima del mapa.
///
/// Mientras el chofer va en camino manda su tramo —lo que la persona quiere
/// saber es cuánto falta para que llegue—, y en cuanto arranca el viaje pasa a
/// mandar el recorrido hasta el destino.
class _Pildora extends StatelessWidget {
  const _Pildora({
    required this.viaje,
    required this.recogida,
    required this.recorrido,
    required this.mostrandoRecogida,
  });

  final Trip viaje;
  final Ruta? recogida;
  final Ruta? recorrido;
  final bool mostrandoRecogida;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final tramo = mostrandoRecogida ? recogida : recorrido;

    final titulo = mostrandoRecogida
        ? (viaje.status == TripStatus.conductorEnOrigen
            ? 'Tu chofer ya está en el punto'
            : 'Tu chofer viene en camino')
        : 'Recorrido hasta el destino';

    // Sin ruta calculada no se inventa un tiempo: se enseña solo el título.
    final detalle =
        tramo == null ? null : '${tramo.duracionTexto} · ${tramo.distanciaTexto}';

    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ride.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: ride.isDark ? const Color(0x99000000) : ride.shadow,
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mostrandoRecogida ? Icons.local_taxi : Icons.route_outlined,
              size: 17,
              color: mostrandoRecogida ? ride.info : ride.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                detalle == null ? titulo : '$titulo · $detalle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.label,
                  fontWeight: FontWeight.w700,
                  color: ride.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El mismo mapa a pantalla completa.
///
/// Dentro de una lista el mapa tiene que ir con los gestos apagados —si no, un
/// arrastre para bajar por la pantalla acaba moviendo el mapa—, así que para
/// poder acercarlo hace falta abrirlo aparte.
class TripRouteFullScreen extends StatelessWidget {
  const TripRouteFullScreen({
    super.key,
    required this.viaje,
    this.chofer,
  });

  final Trip viaje;
  final LatLng? chofer;

  static Future<void> abrir(
    BuildContext context, {
    required Trip viaje,
    LatLng? chofer,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripRouteFullScreen(viaje: viaje, chofer: chofer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ruta del viaje')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LayoutBuilder(
          builder: (context, constraints) => TripRouteMap(
            viaje: viaje,
            chofer: chofer,
            alto: constraints.maxHeight,
          ),
        ),
      ),
    );
  }
}
