import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';

/// Avisos del sistema.
///
/// Los escribe la base mediante triggers, así que llegan aunque la app haya
/// estado cerrada. Realtime solo sirve para refrescar la lista si la persona ya
/// está mirándola.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  sb.RealtimeChannel? _canal;
  List<AppNotification> _avisos = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _canal = FleetService.instance.escucharNotificaciones(_cargar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) sb.Supabase.instance.client.removeChannel(canal);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final avisos = await FleetService.instance.notificaciones();
      if (!mounted) return;
      setState(() {
        _avisos = avisos;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _marcarLeidas() async {
    await FleetService.instance.marcarTodasLeidas();
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final sinLeer = _avisos.where((a) => !a.leida).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (sinLeer > 0)
            TextButton(
              onPressed: _marcarLeidas,
              child: const Text('Marcar leídas'),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _avisos.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.notifications_none,
                            size: 46, color: AppColors.border),
                        SizedBox(height: 14),
                        Center(
                          child: Text(
                            'No tienes notificaciones',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Center(
                          child: Text(
                            'Te avisaremos cuando pase algo con tus viajes.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkMuted),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: _avisos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _Aviso(aviso: _avisos[i]),
                    ),
            ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.aviso});

  final AppNotification aviso;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        // Las no leídas resaltan; las leídas quedan en blanco para que la
        // diferencia se vea de un vistazo.
        color: aviso.leida ? AppColors.surface : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: aviso.leida ? AppColors.border : AppColors.primary,
          width: aviso.leida ? 1 : 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!aviso.leida) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  aviso.titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                aviso.cuando,
                style: const TextStyle(fontSize: 10.5, color: AppColors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            aviso.mensaje,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campana con el contador de avisos sin leer, para las barras superiores.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  sb.RealtimeChannel? _canal;
  int _sinLeer = 0;

  @override
  void initState() {
    super.initState();
    _contar();
    _canal = FleetService.instance.escucharNotificaciones(_contar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) sb.Supabase.instance.client.removeChannel(canal);
    super.dispose();
  }

  Future<void> _contar() async {
    try {
      final n = await FleetService.instance.sinLeer();
      if (mounted) setState(() => _sinLeer = n);
    } catch (_) {
      // Sin conexión la campana simplemente no muestra contador.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Notificaciones',
          icon: const Icon(Icons.notifications_none),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            await _contar();
          },
        ),
        if (_sinLeer > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _sinLeer > 9 ? '9+' : '$_sinLeer',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
