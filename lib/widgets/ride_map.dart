import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// Solo LatLng: latlong2 exporta tambien una clase Path que taparia la de
// Flutter y rompe cualquier CustomPainter de este archivo.
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../services/routing_service.dart';

/// Mapa base de Ride.
///
/// Teselas de OpenStreetMap y rutas de OSRM. **Sin claves, sin cuentas y sin
/// cuotas**: es lo que hace que la app funcione recién clonada, sin
/// configuración previa.
///
/// En modo oscuro las teselas claras se invierten con el filtro de
/// `flutter_map`, porque OSM no publica un estilo oscuro.
///
/// Se probaron proveedores más bonitos —CARTO, Mapbox, Esri— y todos exigen
/// clave, cuenta o las tres cosas. La comparación completa, con lo que costó
/// cada uno, está en `docs/MAPA.md`.
///
/// La atribución a OpenStreetMap es obligatoria: su licencia ODbL la exige allí
/// donde se muestren los datos.
class RideMap extends StatelessWidget {
  const RideMap({
    super.key,
    required this.centro,
    this.zoom = 15,
    this.marcadores = const [],
    this.ruta = const [],
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

  /// Puntos que se unen con una línea: el recorrido del viaje.
  final List<LatLng> ruta;

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

  static const String _urlTeselas =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

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
        TileLayer(
          urlTemplate: _urlTeselas,
          userAgentPackageName: 'com.example.ride',
          // `maxNativeZoom` (19 por defecto) es el tope de lo que sirve OSM: a
          // partir de ahí flutter_map reutiliza la tesela de z19 y la escala.
          //
          // `maxZoom` NO se toca: es hasta dónde se *dibuja* la capa, y su
          // valor por defecto es infinito justamente para que siempre haya
          // teselas. Ponerlo en 19 dejaba el mapa en negro al acercarse más.
          maxNativeZoom: 19,
          // OSM no publica estilo oscuro, asi que en modo oscuro se invierten
          // sus teselas claras con el filtro de flutter_map.
          tileBuilder: context.ride.isDark ? darkModeTileBuilder : null,
        ),
        if (ruta.length >= 2) _CapaRuta(puntos: ruta),
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

/// El trazado del viaje.
///
/// Dibuja de entrada la recta entre los puntos que le pasan —para que siempre
/// haya algo— y, cuando son exactamente dos, le pide a OSRM el recorrido real
/// por calles y lo sustituye al llegar. Si OSRM no responde, se queda la recta.
class _CapaRuta extends StatefulWidget {
  const _CapaRuta({required this.puntos});

  final List<LatLng> puntos;

  @override
  State<_CapaRuta> createState() => _CapaRutaState();
}

class _CapaRutaState extends State<_CapaRuta> {
  List<LatLng>? _porCalles;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void didUpdateWidget(_CapaRuta anterior) {
    super.didUpdateWidget(anterior);
    if (!_mismosExtremos(anterior.puntos, widget.puntos)) {
      _porCalles = null;
      _calcular();
    }
  }

  /// Solo se recalcula si cambió el origen o el destino. El widget se
  /// reconstruye a cada rato —al moverse el chofer, por ejemplo— y no hay que
  /// castigar al servidor de OSRM por eso.
  static bool _mismosExtremos(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length || a.isEmpty) return a.length == b.length;
    return a.first == b.first && a.last == b.last;
  }

  Future<void> _calcular() async {
    final puntos = widget.puntos;
    if (puntos.length != 2) return;

    final ruta = await RoutingService.instance.entre(puntos.first, puntos.last);
    if (!mounted || ruta == null) return;
    setState(() => _porCalles = ruta.puntos);
  }

  @override
  Widget build(BuildContext context) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: _porCalles ?? widget.puntos,
          strokeWidth: 5,
          color: AppColors.primary,
          borderStrokeWidth: 1.5,
          borderColor: Colors.white.withValues(alpha: 0.7),
        ),
      ],
    );
  }
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

/// Atribución a OpenStreetMap y a CARTO.
///
/// No es decorativa y no se puede quitar: la licencia ODbL obliga a acreditar
/// la fuente de los datos allí donde se muestren, y las condiciones de CARTO
/// obligan a acreditar también el estilo.
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
          '© OpenStreetMap',
          style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
        ),
      ),
    );
  }
}
