import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/trip.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
import 'rate_trip_sheet.dart';

/// Trabajo del chofer: ponerse en línea, tomar solicitudes y llevar el viaje.
///
/// Las solicitudes llegan por Realtime. La política
/// `viajes_difusion_conductores` es la que decide si este chofer las ve: solo
/// aparecen si está aprobado y disponible.
class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  sb.RealtimeChannel? _canal;

  DriverState _estado = const DriverState.sinCuenta();
  List<Trip> _solicitudes = const [];
  Trip? _activo;

  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  bool _calificacionOfrecida = false;

  @override
  void initState() {
    super.initState();
    _refrescar();
    _canal = RideService.instance.escucharViajes(_refrescar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) RideService.instance.cerrarCanal(canal);
    super.dispose();
  }

  Future<void> _refrescar() async {
    try {
      final estado = await RideService.instance.estadoConductor();
      final activo = await RideService.instance.viajeActivo();
      // Si ya lleva un viaje, la lista de solicitudes no aporta nada.
      final solicitudes = activo == null && estado.puedeTrabajar && estado.disponible
          ? await RideService.instance.solicitudesAbiertas()
          : <Trip>[];

      if (!mounted) return;
      setState(() {
        _estado = estado;
        _activo = activo;
        _solicitudes = solicitudes;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos actualizar tus viajes.';
        _cargando = false;
      });
    }
  }

  Future<void> _accion(Future<void> Function() operacion) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await operacion();
      await _refrescar();
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      // Si otro chofer se adelantó, la lista debe reflejarlo.
      await _refrescar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _finalizar(Trip viaje) async {
    await _accion(() async {
      final total = await RideService.instance.finalizar(viaje.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Viaje cerrado. Total \$${total.toStringAsFixed(2)}')),
      );
    });

    // Calificar al pasajero, una sola vez.
    if (!_calificacionOfrecida && mounted) {
      _calificacionOfrecida = true;
      if (!await RideService.instance.yaCalifico(viaje.id)) {
        if (!mounted) return;
        await mostrarHojaCalificacion(
          context,
          viajeId: viaje.id,
          calificadoId: viaje.pasajeroId,
          titulo: '¿Cómo estuvo el pasajero?',
          subtitulo: 'Califica a ${viaje.pasajeroNombre}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Viajes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refrescar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _Disponibilidad(
                    estado: _estado,
                    ocupado: _ocupado,
                    onCambiar: (valor) => _accion(
                      () => RideService.instance.cambiarDisponibilidad(valor),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 18),
                  if (_activo != null)
                    _ViajeActivo(
                      viaje: _activo!,
                      ocupado: _ocupado,
                      onAvanzar: () => _accion(
                        () => RideService.instance.avanzar(_activo!.id).then((_) {}),
                      ),
                      onFinalizar: () => _finalizar(_activo!),
                      onCancelar: () => _accion(
                        () => RideService.instance.cancelar(_activo!.id),
                      ),
                    )
                  else
                    _ListaSolicitudes(
                      estado: _estado,
                      solicitudes: _solicitudes,
                      ocupado: _ocupado,
                      onAceptar: (viaje) => _accion(
                        () => RideService.instance.aceptar(viaje.id),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Disponibilidad extends StatelessWidget {
  const _Disponibilidad({
    required this.estado,
    required this.ocupado,
    required this.onCambiar,
  });

  final DriverState estado;
  final bool ocupado;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final bloqueado = !estado.puedeTrabajar;

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: estado.disponible ? context.ride.success : context.ride.border,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  estado.disponible ? 'En línea' : 'Fuera de línea',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.ride.ink,
                  ),
                ),
              ),
              Switch(
                value: estado.disponible,
                onChanged: (bloqueado || ocupado) ? null : onCambiar,
              ),
            ],
          ),
          if (bloqueado) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.ride.infoSoft,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Text(
                estado.motivoBloqueo,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: context.ride.ink,
                ),
              ),
            ),
          ] else if (!estado.disponible) ...[
            const SizedBox(height: 8),
            Text(
              'Ponte en línea para recibir solicitudes de viaje.',
              style: TextStyle(fontSize: 11.5, color: context.ride.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListaSolicitudes extends StatelessWidget {
  const _ListaSolicitudes({
    required this.estado,
    required this.solicitudes,
    required this.ocupado,
    required this.onAceptar,
  });

  final DriverState estado;
  final List<Trip> solicitudes;
  final bool ocupado;
  final ValueChanged<Trip> onAceptar;

  @override
  Widget build(BuildContext context) {
    if (!estado.puedeTrabajar || !estado.disponible) {
      return const _Vacio(
        icono: Icons.nightlight_outlined,
        titulo: 'Sin solicitudes',
        detalle: 'Ponte en línea para empezar a recibir viajes.',
      );
    }

    if (solicitudes.isEmpty) {
      return const _Vacio(
        icono: Icons.search,
        titulo: 'Buscando pasajeros',
        detalle: 'Te avisamos apenas alguien pida un viaje cerca.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${solicitudes.length} ${solicitudes.length == 1 ? 'solicitud' : 'solicitudes'} disponibles',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.ride.inkMuted,
          ),
        ),
        const SizedBox(height: 12),
        for (final viaje in solicitudes) ...[
          RideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        viaje.pasajeroNombre,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.ride.ink,
                        ),
                      ),
                    ),
                    Text(
                      '\$${viaje.tarifaEstimada.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: context.ride.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MiniRuta(viaje: viaje),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: ocupado ? null : () => onAceptar(viaje),
                  child: const Text('Aceptar ruta'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ViajeActivo extends StatelessWidget {
  const _ViajeActivo({
    required this.viaje,
    required this.ocupado,
    required this.onAvanzar,
    required this.onFinalizar,
    required this.onCancelar,
  });

  final Trip viaje;
  final bool ocupado;
  final VoidCallback onAvanzar;
  final VoidCallback onFinalizar;
  final VoidCallback onCancelar;

  /// Qué botón mostrar según dónde va el recorrido.
  String? get _siguientePaso => switch (viaje.status) {
        TripStatus.aceptado => 'Voy en camino',
        TripStatus.conductorEnCamino => 'Llegué al punto',
        TripStatus.conductorEnOrigen => 'Iniciar viaje',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: viaje.status.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          child: Row(
            children: [
              Icon(Icons.local_taxi, size: 20, color: viaje.status.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  viaje.status.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: viaje.status.color,
                  ),
                ),
              ),
              Text(
                '\$${viaje.montoVigente.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: context.ride.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        RideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: context.ride.inkMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      viaje.pasajeroNombre,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.ride.ink,
                      ),
                    ),
                  ),
                  if (viaje.pasajeroTelefono != null)
                    Text(
                      viaje.pasajeroTelefono!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.ride.accent,
                      ),
                    ),
                ],
              ),
              const Divider(height: 22),
              _MiniRuta(viaje: viaje),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_siguientePaso != null)
          FilledButton(
            onPressed: ocupado ? null : onAvanzar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_siguientePaso!),
          ),
        if (viaje.status == TripStatus.enCurso)
          FilledButton(
            onPressed: ocupado ? null : onFinalizar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: context.ride.success,
            ),
            child: const Text('Finalizar viaje'),
          ),
        if (viaje.status.sePuedeCancelar) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: ocupado ? null : onCancelar,
            style: TextButton.styleFrom(foregroundColor: context.ride.danger),
            child: const Text('Cancelar viaje'),
          ),
        ],
      ],
    );
  }
}

class _MiniRuta extends StatelessWidget {
  const _MiniRuta({required this.viaje});

  final Trip viaje;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Linea(
          icono: Icons.my_location,
          color: context.ride.accent,
          texto: viaje.origenTexto,
        ),
        const SizedBox(height: 7),
        _Linea(
          icono: Icons.place_outlined,
          color: context.ride.success,
          texto: viaje.destinoTexto,
        ),
      ],
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.icono, required this.color, required this.texto});

  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: context.ride.ink),
          ),
        ),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 46),
      child: Column(
        children: [
          Icon(icono, size: 42, color: context.ride.border),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.ride.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
          ),
        ],
      ),
    );
  }
}
