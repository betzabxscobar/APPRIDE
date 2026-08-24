import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/app_user.dart';
import '../../widgets/ride_card.dart';
import 'account_sheet.dart';

/// Home del rol pasajero. Por ahora es la maqueta estática del diseño:
/// el flujo de reserva se implementa en la siguiente etapa.
class PassengerHomeScreen extends StatelessWidget {
  const PassengerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                IconButton(
                  onPressed: () => showAccountSheet(context, user),
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Cuenta',
                ),
              ],
            ),
            const SizedBox(height: 18),
            RideCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  const _DestinationRow(
                    icon: Icons.place_outlined,
                    label: '¿A dónde quieres llegar?',
                  ),
                  const Divider(height: 1),
                  _DestinationRow(
                    icon: Icons.schedule,
                    label: 'Agregar destino frecuente',
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
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
