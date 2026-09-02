import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/trip.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/ride_card.dart';
import '../trips/trip_tracking_screen.dart';

/// Todos los viajes de la plataforma, para la administración.
///
/// No filtra en el cliente: las políticas RLS son las que dejan a una cuenta
/// administrativa ver los viajes ajenos (`viajes_participante` incluye
/// `es_administrativo()`). Un pasajero que llamara a esto vería solo los
/// suyos.
class AdminTripsPanel extends StatefulWidget {
  const AdminTripsPanel({super.key});

  @override
  State<AdminTripsPanel> createState() => _AdminTripsPanelState();
}

class _AdminTripsPanelState extends State<AdminTripsPanel> {
  /// `null` es «todos».
  String? _filtro;

  List<Trip> _viajes = const [];
  bool _cargando = true;
  String? _error;

  static const List<(String?, String)> _filtros = [
    (null, 'Todos'),
    ('BUSCANDO_CONDUCTOR', 'Buscando'),
    ('EN_CURSO', 'En curso'),
    ('FINALIZADO', 'Finalizados'),
    ('CANCELADO', 'Cancelados'),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final lista = await RideService.instance.todosLosViajes(estado: _filtro);
      if (!mounted) return;
      setState(() {
        _viajes = lista;
        _cargando = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar los viajes.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              for (final (valor, etiqueta) in _filtros)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(etiqueta),
                    selected: _filtro == valor,
                    onSelected: (_) {
                      setState(() => _filtro = valor);
                      _cargar();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (!_cargando && _viajes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              '${_viajes.length} '
              '${_viajes.length == 1 ? 'viaje' : 'viajes'}'
              '${_filtro == null ? '' : ' con ese estado'}',
              style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
            ),
          ),
        Expanded(
          child: _cargando
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
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(
                            children: [
                              Icon(Icons.route_outlined,
                                  size: 44, color: ride.border),
                              const SizedBox(height: 14),
                              Text(
                                'No hay viajes con ese estado.',
                                style: TextStyle(
                                  fontSize: AppText.small,
                                  color: ride.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final v in _viajes) ...[
                          _FilaViaje(
                            viaje: v,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TripTrackingScreen(viajeId: v.id),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _FilaViaje extends StatelessWidget {
  const _FilaViaje({required this.viaje, required this.onTap});

  final Trip viaje;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

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
                  color: viaje.status.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                viaje.status.label,
                style: TextStyle(
                  fontSize: AppText.micro,
                  fontWeight: FontWeight.w800,
                  color: viaje.status.color,
                ),
              ),
              const Spacer(),
              Text(
                '\$${viaje.montoVigente.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: AppText.small,
                  fontWeight: FontWeight.w900,
                  color: ride.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Linea(
            icono: Icons.person_outline,
            texto: viaje.pasajeroNombre,
            color: ride.accent,
          ),
          const SizedBox(height: 4),
          _Linea(
            icono: Icons.drive_eta_outlined,
            texto: viaje.conductorNombre ?? 'Sin chofer asignado',
            color: viaje.conductorId == null ? ride.inkFaint : ride.success,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CategoryChip(
                nombre: viaje.categoriaNombre,
                icono: viaje.categoriaIcono,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${viaje.origenTexto} → ${viaje.destinoTexto}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

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
