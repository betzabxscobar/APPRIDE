import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/trip.dart';
import '../../services/auth_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/ride_card.dart';
import 'trip_tracking_screen.dart';

/// Los viajes de la persona, del más nuevo al más viejo.
///
/// `RideService.historial()` existía desde el principio y **no la llamaba
/// nadie**: la pestaña «Viajes» de la barra inferior no hacía nada. Esta es la
/// pantalla que faltaba.
///
/// Sirve igual para pasajero y para chofer: las políticas RLS ya limitan las
/// filas a los viajes propios, así que no hay que preguntar por rol. Lo único
/// que cambia es a quién se nombra en cada fila — al chofer si eres pasajero, y
/// al pasajero si eres chofer.
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<Trip> _viajes = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await RideService.instance.historial(limite: 50);
      if (!mounted) return;
      setState(() {
        _viajes = lista;
        _cargando = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus viajes.';
        _cargando = false;
      });
    }
  }

  Future<void> _abrir(Trip viaje) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripTrackingScreen(viajeId: viaje.id)),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final miId = AuthService.instance.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis viajes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  if (_viajes.isEmpty && _error == null)
                    const _SinViajes()
                  else
                    for (final v in _viajes) ...[
                      _FilaViaje(
                        viaje: v,
                        soyElChofer: miId != null && v.conductorId == miId,
                        onTap: () => _abrir(v),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}

class _SinViajes extends StatelessWidget {
  const _SinViajes();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Icon(Icons.route_outlined, size: 46, color: ride.border),
          const SizedBox(height: 16),
          Text(
            'Todavía no has hecho ningún viaje',
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: FontWeight.w700,
              color: ride.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuando hagas uno, aparecerá aquí con su recorrido y su precio.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _FilaViaje extends StatelessWidget {
  const _FilaViaje({
    required this.viaje,
    required this.soyElChofer,
    required this.onTap,
  });

  final Trip viaje;

  /// Cambia a quién se nombra: si conduje yo, interesa el pasajero.
  final bool soyElChofer;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final estado = viaje.status;

    final conQuien = soyElChofer
        ? viaje.pasajeroNombre
        : (viaje.conductorNombre ?? 'Sin chofer asignado');

    return RideCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: estado.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                estado.label,
                style: TextStyle(
                  fontSize: AppText.micro,
                  fontWeight: FontWeight.w800,
                  color: estado.color,
                ),
              ),
              const Spacer(),
              Text(
                _cuando(viaje.fechaSolicitud),
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: ride.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Punto(
            icono: Icons.my_location,
            color: ride.accent,
            texto: viaje.origenTexto,
          ),
          const SizedBox(height: 5),
          _Punto(
            icono: Icons.place_outlined,
            color: ride.success,
            texto: viaje.destinoTexto,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CategoryChip(
                nombre: viaje.categoriaNombre,
                icono: viaje.categoriaIcono,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conQuien,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
              ),
              Text(
                '\$${viaje.montoVigente.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: AppText.h3,
                  fontWeight: FontWeight.w900,
                  color: ride.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// «hace 20 min», «ayer», «12/08/2026».
  ///
  /// Lo reciente en relativo, que es como se piensa en un viaje de hace un
  /// rato; a partir de una semana, la fecha, que ya es lo que se busca.
  static String _cuando(DateTime f) {
    final d = DateTime.now().difference(f);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays == 1) return 'ayer';
    if (d.inDays < 7) return 'hace ${d.inDays} días';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/${f.year}';
  }
}

class _Punto extends StatelessWidget {
  const _Punto({
    required this.icono,
    required this.color,
    required this.texto,
  });

  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 14, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppText.label,
              color: context.ride.ink,
            ),
          ),
        ),
      ],
    );
  }
}
