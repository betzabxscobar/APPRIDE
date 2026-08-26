import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/app_user.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import 'account_sheet.dart';

/// Home del rol conductor. Maqueta estática del diseño; el flujo de aceptar
/// rutas reales llega en la siguiente etapa.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _available = true;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      appBar: const ViewingAsBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            RideCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.greenSoft,
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Modo conductor',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Switch(
                    value: _available,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                    onChanged: (v) => setState(() => _available = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _available ? AppColors.green : AppColors.inkMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _available ? 'Estás disponible' : 'No estás disponible',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => showAccountSheet(context, user),
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Cuenta',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Zona: Quito Norte',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const Spacer(),
                TextButton(onPressed: () {}, child: const Text('Cambiar')),
              ],
            ),
            if (user.vehicle != null) ...[
              const SizedBox(height: 10),
              RideCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.directions_car_outlined,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.vehicle!.summary,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.vehicle!.plate,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            const Text(
              'Oportunidades para ti',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Ordenadas por compatibilidad y retorno',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 14),
            const _OpportunityCard(
              index: 1,
              tag: 'Alta compatibilidad',
              match: '92%',
              from: 'Av. 6 de Diciembre',
              to: 'Cumbayá',
              earnings: '\$8.40',
              duration: '14 min',
              distance: '6.2 km',
            ),
            const SizedBox(height: 14),
            const _OpportunityCard(
              index: 2,
              tag: 'Buen retorno',
              match: '78%',
              from: 'La Carolina',
              to: 'Calderón',
              earnings: '\$9.10',
              duration: '18 min',
              distance: '8.1 km',
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _DriverNavBar(),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.index,
    required this.tag,
    required this.match,
    required this.from,
    required this.to,
    required this.earnings,
    required this.duration,
    required this.distance,
  });

  final int index;
  final String tag;
  final String match;
  final String from;
  final String to;
  final String earnings;
  final String duration;
  final String distance;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.primary,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  match,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('Desde'),
                    Text(from, style: _placeStyle),
                    const SizedBox(height: 8),
                    const _Label('Hasta'),
                    Text(to, style: _placeStyle),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Tú ganas',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      earnings,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Text(duration, style: _metaStyle),
              const SizedBox(width: 14),
              const Icon(
                Icons.route_outlined,
                size: 14,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Text(distance, style: _metaStyle),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () {},
                  child: const Text('Aceptar ruta'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text('Omitir'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const TextStyle _placeStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static const TextStyle _metaStyle = TextStyle(
    fontSize: 12,
    color: AppColors.inkMuted,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
    );
  }
}

class _DriverNavBar extends StatelessWidget {
  const _DriverNavBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          label: 'Ganancias',
        ),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          label: 'Viajes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Cuenta',
        ),
      ],
    );
  }
}
