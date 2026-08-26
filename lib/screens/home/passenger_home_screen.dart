import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/app_user.dart';
import '../../models/trip.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/payments/payment_methods_screen.dart';
import '../../screens/trips/request_trip_screen.dart';
import '../../screens/trips/trip_tracking_screen.dart';
import '../../services/ride_service.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import 'account_sheet.dart';

/// Home del rol pasajero: punto de entrada para pedir un viaje y seguirlo.
class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  sb.RealtimeChannel? _canal;
  Trip? _activo;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Si el chofer cambia el estado del viaje, la tarjeta se actualiza sola.
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
      final viaje = await RideService.instance.viajeActivo();
      if (mounted) setState(() => _activo = viaje);
    } catch (_) {
      // Sin conexión la pantalla sigue usable; el viaje aparece al reintentar.
    }
  }

  Future<void> _pedirViaje() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RequestTripScreen()),
    );
    if (id == null || !mounted) return;
    await _abrirSeguimiento(id);
  }

  Future<void> _abrirSeguimiento(String viajeId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripTrackingScreen(viajeId: viajeId)),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      // Solo aparece si un administrador está mirando esta pantalla; para un
      // pasajero de verdad no ocupa espacio.
      appBar: const ViewingAsBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¡Hola, ${user.firstName}! 👋',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '¿A dónde vamos hoy?',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const NotificationsBell(),
                IconButton(
                  onPressed: () => showAccountSheet(context, user),
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Cuenta',
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_activo != null) ...[
              _ViajeEnCurso(
                viaje: _activo!,
                onAbrir: () => _abrirSeguimiento(_activo!.id),
              ),
              const SizedBox(height: 18),
            ] else ...[
              InkWell(
                onTap: _pedirViaje,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                child: RideCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      const _DestinationRow(
                        icon: Icons.place_outlined,
                        label: '¿A dónde quieres llegar?',
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const Divider(height: 1),
                      _DestinationRow(
                        icon: Icons.my_location,
                        label: 'Usar mi ubicación como punto de partida',
                        trailing: const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _pedirViaje,
                icon: const Icon(Icons.local_taxi, size: 20),
                label: const Text('Pedir un viaje'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentMethodsScreen(),
                  ),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
                label: const Text('Métodos de pago'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _SafePointCard(),
            const SizedBox(height: 22),
            const Text(
              'Elige tu prioridad de ruta',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const _PriorityCard(
              icon: Icons.bolt,
              color: AppColors.primary,
              background: AppColors.primarySoft,
              title: 'Más rápido',
              subtitle: 'Llegas antes con la mejor ruta.',
            ),
            const SizedBox(height: 12),
            const _PriorityCard(
              icon: Icons.verified_user_outlined,
              color: AppColors.green,
              background: AppColors.greenSoft,
              title: 'Más seguro',
              subtitle: 'Rutas con mejor historial de seguridad.',
            ),
            const SizedBox(height: 12),
            const _PriorityCard(
              icon: Icons.savings_outlined,
              color: AppColors.purple,
              background: AppColors.purpleSoft,
              title: 'Más económico',
              subtitle: 'Ahorra más con opciones eficientes.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _PassengerNavBar(),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SafePointCard extends StatelessWidget {
  const _SafePointCard();

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Punto Ride seguro',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'Verificado',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Av. Amazonas 1234 y Naciones Unidas\nQuito',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(
                Icons.directions_walk,
                size: 16,
                color: AppColors.inkMuted,
              ),
              SizedBox(width: 6),
              Text(
                '3 min caminando',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      color: background,
      borderColor: background,
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.inkMuted,
          ),
        ],
      ),
    );
  }
}

class _PassengerNavBar extends StatelessWidget {
  const _PassengerNavBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          label: 'Viajes',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          label: 'Mensajes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Cuenta',
        ),
      ],
    );
  }
}

/// Tarjeta del viaje en marcha, con acceso directo al seguimiento.
class _ViajeEnCurso extends StatelessWidget {
  const _ViajeEnCurso({required this.viaje, required this.onAbrir});

  final Trip viaje;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAbrir,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: viaje.status.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: viaje.status.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: viaje.status.color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viaje.status.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: viaje.status.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hacia ${viaje.destinoTexto}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
