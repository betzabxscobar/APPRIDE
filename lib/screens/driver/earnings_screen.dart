import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// Cuánto lleva ganado el chofer.
///
/// La pestaña «Ganancias» de la barra inferior no llevaba a ningún sitio. Esta
/// es la pantalla que faltaba.
///
/// Los números los calcula Postgres (`ganancias_conductor`), no la app: el
/// dinero no lo puede decir el teléfono. Y el reparto de cada viaje sale del
/// porcentaje que tenía **su** tarifa, no del de hoy — si mañana cambia el
/// reparto, lo ya cobrado no se reescribe.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, DriverEarnings> _datos = const {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final datos = await RideService.instance.ganancias();
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _cargando = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus ganancias.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final hoy = _datos['hoy'];

    return Scaffold(
      appBar: AppBar(title: const Text('Ganancias')),
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
                  _Hoy(datos: hoy),
                  const SizedBox(height: 22),
                  Text(
                    'RESUMEN',
                    style: TextStyle(
                      fontSize: AppText.micro,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: ride.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Periodo(titulo: 'Esta semana', datos: _datos['semana']),
                  const SizedBox(height: 10),
                  _Periodo(titulo: 'Este mes', datos: _datos['mes']),
                  const SizedBox(height: 10),
                  _Periodo(titulo: 'Desde que empezaste', datos: _datos['total']),
                  const SizedBox(height: 20),
                  _NotaComision(total: _datos['total']),
                ],
              ),
            ),
    );
  }
}

/// Lo de hoy, en grande: es el número que un chofer mira al terminar el día.
class _Hoy extends StatelessWidget {
  const _Hoy({required this.datos});

  final DriverEarnings? datos;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final d = datos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ride.success.withValues(alpha: ride.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: ride.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOY',
            style: TextStyle(
              fontSize: AppText.micro,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: ride.success,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${(d?.ganado ?? 0).toStringAsFixed(2)}',
            style: AppTheme.display(
              AppText.hero,
              color: ride.ink,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d == null || d.viajes == 0
                ? 'Todavía no has cerrado ningún viaje hoy.'
                : '${d.viajes} ${d.viajes == 1 ? 'viaje' : 'viajes'} · '
                    'los pasajeros pagaron \$${d.bruto.toStringAsFixed(2)}',
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Periodo extends StatelessWidget {
  const _Periodo({required this.titulo, required this.datos});

  final String titulo;
  final DriverEarnings? datos;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final d = datos;

    return RideCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w700,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d == null || d.viajes == 0
                      ? 'Sin viajes'
                      : '${d.viajes} ${d.viajes == 1 ? 'viaje' : 'viajes'}',
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${(d?.ganado ?? 0).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: AppText.h3,
              fontWeight: FontWeight.w900,
              color: ride.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// De dónde sale la diferencia entre lo que paga el pasajero y lo que llega.
///
/// Se dice claramente en vez de dejar que el chofer lo descubra restando: una
/// comisión que aparece sin explicación es lo que hace desconfiar de una app.
class _NotaComision extends StatelessWidget {
  const _NotaComision({required this.total});

  final DriverEarnings? total;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final d = total;
    if (d == null || d.viajes == 0) return const SizedBox.shrink();

    final porcentaje = d.bruto == 0 ? 0.0 : (d.ganado / d.bruto) * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ride.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: ride.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: ride.inkMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Te llevas el ${porcentaje.round()} % de lo que paga el pasajero. '
              'En total han pagado \$${d.bruto.toStringAsFixed(2)} y la comisión '
              'de la app ha sido \$${d.comision.toStringAsFixed(2)}.',
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.45,
                color: ride.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
