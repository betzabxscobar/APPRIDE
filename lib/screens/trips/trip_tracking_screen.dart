import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/trip.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_map.dart';
import 'rate_trip_sheet.dart';

/// Seguimiento del viaje, del lado del pasajero.
///
/// Se actualiza con Realtime en vez de preguntar cada pocos segundos: Supabase
/// avisa cuando la fila cambia y solo emite lo que RLS dejaría leer, así que
/// nadie recibe viajes ajenos.
class TripTrackingScreen extends StatefulWidget {
  const TripTrackingScreen({super.key, required this.viajeId});

  final String viajeId;

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  sb.RealtimeChannel? _canal;
  Trip? _viaje;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  bool _calificacionOfrecida = false;

  /// Dónde va el chofer ahora mismo. Se refresca con cada aviso de Realtime.
  ({double lat, double lng})? _posicionChofer;

  @override
  void initState() {
    super.initState();
    _cargar();
    _canal = RideService.instance.escucharViajes(_cargar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) RideService.instance.cerrarCanal(canal);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final viaje = await RideService.instance.porId(widget.viajeId);
      if (!mounted) return;
      setState(() {
        _viaje = viaje;
        _cargando = false;
      });
      // Solo tiene sentido seguir al chofer mientras el viaje está vivo.
      if (viaje != null && viaje.status.tieneConductor) {
        final pos = await RideService.instance.posicionDelChofer(viaje.id);
        if (mounted) setState(() => _posicionChofer = pos);
      }

      if (viaje != null && viaje.status == TripStatus.finalizado) {
        _ofrecerCalificacion(viaje);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar el viaje.';
        _cargando = false;
      });
    }
  }

  /// Al terminar el viaje se abre la calificación una sola vez.
  ///
  /// Se comprueba contra la base porque Realtime puede reemitir el mismo
  /// cambio y no queremos abrir la hoja dos veces.
  Future<void> _ofrecerCalificacion(Trip viaje) async {
    if (_calificacionOfrecida || viaje.conductorId == null) return;
    _calificacionOfrecida = true;

    if (await RideService.instance.yaCalifico(viaje.id)) return;
    if (!mounted) return;

    await mostrarHojaCalificacion(
      context,
      viajeId: viaje.id,
      calificadoId: viaje.conductorId!,
      titulo: '¿Cómo estuvo tu viaje?',
      subtitulo: 'Califica a ${viaje.conductorNombre ?? 'tu chofer'}',
    );
  }

  Future<void> _cancelar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar el viaje?'),
        content: const Text('Se avisará al chofer si ya tenías uno asignado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await RideService.instance.cancelar(widget.viajeId);
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viaje = _viaje;

    return Scaffold(
      appBar: AppBar(title: const Text('Tu viaje')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : viaje == null
              ? const Center(child: Text('No encontramos este viaje.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    _MapaViaje(viaje: viaje, chofer: _posicionChofer),
                    const SizedBox(height: 16),
                    _EstadoActual(viaje: viaje),
                    const SizedBox(height: 16),
                    _Ruta(viaje: viaje),
                    if (viaje.status.tieneConductor) ...[
                      const SizedBox(height: 16),
                      _TarjetaConductor(viaje: viaje),
                    ],
                    const SizedBox(height: 16),
                    _TarjetaPrecio(viaje: viaje),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    if (viaje.status.sePuedeCancelar)
                      OutlinedButton(
                        onPressed: _ocupado ? null : _cancelar,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        child: Text(
                          _ocupado ? 'Cancelando…' : 'Cancelar viaje',
                        ),
                      ),
                    if (viaje.status.esFinal)
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Volver al inicio'),
                      ),
                  ],
                ),
    );
  }
}

class _EstadoActual extends StatelessWidget {
  const _EstadoActual({required this.viaje});

  final Trip viaje;

  @override
  Widget build(BuildContext context) {
    final estado = viaje.status;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (estado.esActivo)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: estado.color,
                  ),
                )
              else
                Icon(
                  estado == TripStatus.finalizado
                      ? Icons.check_circle
                      : Icons.cancel,
                  size: 18,
                  color: estado.color,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  estado.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: estado.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            estado.hint,
            style: const TextStyle(fontSize: 13, color: AppColors.ink),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: estado.progreso,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              color: estado.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ruta extends StatelessWidget {
  const _Ruta({required this.viaje});

  final Trip viaje;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Column(
        children: [
          _Fila(
            icono: Icons.my_location,
            color: AppColors.primary,
            titulo: 'Origen',
            valor: viaje.origenTexto,
          ),
          const Divider(height: 22),
          _Fila(
            icono: Icons.place_outlined,
            color: AppColors.green,
            titulo: 'Destino',
            valor: viaje.destinoTexto,
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 19, color: color),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaConductor extends StatelessWidget {
  const _TarjetaConductor({required this.viaje});

  final Trip viaje;

  @override
  Widget build(BuildContext context) {
    final nombre = viaje.conductorNombre ?? 'Chofer asignado';
    final iniciales = nombre.trim().isEmpty
        ? '?'
        : nombre.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join().toUpperCase();

    return RideCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.greenSoft,
            child: Text(
              iniciales,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.green,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  viaje.vehiculoResumen,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
                if (viaje.conductorCalificacion != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 13, color: Color(0xFFF5A623)),
                      const SizedBox(width: 3),
                      Text(
                        viaje.conductorCalificacion!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (viaje.vehiculoPlaca != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                viaje.vehiculoPlaca!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TarjetaPrecio extends StatelessWidget {
  const _TarjetaPrecio({required this.viaje});

  final Trip viaje;

  @override
  Widget build(BuildContext context) {
    final cerrado = viaje.tarifaFinal != null;

    return RideCard(
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              cerrado ? 'Total del viaje' : 'Precio estimado',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            '\$${viaje.montoVigente.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mapa del viaje: origen, destino y el chofer si ya va en camino.
class _MapaViaje extends StatelessWidget {
  const _MapaViaje({required this.viaje, required this.chofer});

  final Trip viaje;
  final ({double lat, double lng})? chofer;

  @override
  Widget build(BuildContext context) {
    final origen = viaje.origenLat == null || viaje.origenLng == null
        ? null
        : LatLng(viaje.origenLat!, viaje.origenLng!);
    final destino = viaje.destinoLat == null || viaje.destinoLng == null
        ? null
        : LatLng(viaje.destinoLat!, viaje.destinoLng!);

    // Sin coordenadas no hay nada que dibujar; el resto de la pantalla sirve
    // igual.
    if (origen == null && destino == null) return const SizedBox.shrink();

    final marcadores = <MapMarker>[
      if (origen != null) MapMarker.origen(origen),
      if (destino != null) MapMarker.destino(destino),
      if (chofer != null) MapMarker.chofer(LatLng(chofer!.lat, chofer!.lng)),
    ];

    // El mapa se centra en el chofer mientras se mueve; si todavía no reportó,
    // en el punto de recogida.
    final centro = chofer != null
        ? LatLng(chofer!.lat, chofer!.lng)
        : (origen ?? destino!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: SizedBox(
        height: 190,
        child: RideMap(
          centro: centro,
          zoom: chofer != null ? 15 : 13,
          marcadores: marcadores,
          ruta: origen != null && destino != null ? [origen, destino] : const [],
        ),
      ),
    );
  }
}
