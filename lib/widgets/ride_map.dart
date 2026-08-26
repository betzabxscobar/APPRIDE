import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// Solo LatLng: latlong2 exporta tambien una clase Path que taparia la de
// Flutter y rompe cualquier CustomPainter de este archivo.
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/app_colors.dart';

/// Mapa base de Ride.
///
/// Usa teselas de OpenStreetMap, que no necesitan clave. La política de uso de
/// sus servidores pide identificar la aplicación y no abusar: para desarrollo y
/// demos alcanza, pero con usuarios reales hay que pasar a un proveedor de
/// teselas propio o de pago. El cambio se hace en [_urlTeselas].
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
  });

  final LatLng centro;
  final double zoom;
  final List<MapMarker> marcadores;

  /// Puntos que se unen con una línea: el recorrido del viaje.
  final List<LatLng> ruta;

  final MapController? controlador;
  final void Function(LatLng punto)? onTap;
  final bool interactivo;

  static const String _urlTeselas =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controlador,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: zoom,
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
          maxZoom: 19,
        ),
        if (ruta.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: ruta,
                strokeWidth: 4,
                color: AppColors.primary,
              ),
            ],
          ),
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
        const _CreditoOSM(),
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

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icono});

  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Column(
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

/// Atribución a OpenStreetMap.
///
/// No es decorativa: su licencia ODbL obliga a acreditar la fuente de los
/// datos allí donde se muestren.
class _CreditoOSM extends StatelessWidget {
  const _CreditoOSM();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(fontSize: 9, color: AppColors.inkMuted),
        ),
      ),
    );
  }
}
