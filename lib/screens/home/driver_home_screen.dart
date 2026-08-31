import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_theme.dart';
import '../../core/map_defaults.dart';
import '../../core/ride_colors.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';
import '../../models/trip.dart';
import '../../screens/driver/driver_profile_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/trips/driver_trips_screen.dart';
import '../../services/location_service.dart';
import '../../services/auth_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_map.dart';
import 'account_sheet.dart';

/// Home del rol conductor.
///
/// Mismo patrón que la pantalla del pasajero: el mapa de fondo y una hoja
/// arrastrable con el estado, los accesos y las oportunidades. Para quien
/// conduce el mapa no es decoración: es dónde está y qué tiene alrededor.
///
/// Las oportunidades siguen siendo maqueta; el flujo de aceptar rutas reales
/// llega en la siguiente etapa.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const double _hojaMinima = 0.36;
  static const double _hojaInicial = 0.52;

  final MapController _mapa = MapController();

  sb.RealtimeChannel? _canal;
  DriverState _estado = const DriverState.sinCuenta();
  Trip? _activo;
  bool _cambiando = false;

  /// Dónde está el chofer y con cuánto margen de error.
  ({LatLng punto, double precision})? _yo;

  bool _buscandoUbicacion = true;
  String? _errorUbicacion;
  bool _mapaListo = false;
  double _hoja = _hojaInicial;

  /// Refleja el estado real guardado en `public.conductores`, no una bandera
  /// local: antes el interruptor cambiaba de color sin que el servidor se
  /// enterara, así que la pantalla mentía.
  bool get _available => _estado.disponible;

  @override
  void initState() {
    super.initState();
    _cargar();
    _ubicar();
    try {
      _canal = RideService.instance.escucharViajes(_cargar);
    } catch (_) {
      // Si Realtime no arranca, la pantalla sigue en pie con los datos que
      // trae `_cargar`. Sin este try la excepción sale de initState y deja la
      // pantalla en rojo.
    }
  }

  @override
  void dispose() {
    _latido?.cancel();
    final canal = _canal;
    if (canal != null) RideService.instance.cerrarCanal(canal);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final estado = await RideService.instance.estadoConductor();
      final activo = await RideService.instance.viajeActivo();
      if (mounted) {
        setState(() {
          _estado = estado;
          _activo = activo;
        });
        _ajustarLatido();
      }
    } catch (_) {
      // Sin conexión la pantalla sigue usable.
    }
  }

  Future<void> _ubicar() async {
    setState(() {
      _buscandoUbicacion = true;
      _errorUbicacion = null;
    });

    try {
      final pos = await LocationService.instance.posicionActual();
      if (!mounted) return;
      setState(() {
        _yo = (punto: LatLng(pos.lat, pos.lng), precision: pos.precision);
        _buscandoUbicacion = false;
      });
      _centrar();
    } on LocationUnavailable catch (e) {
      // Aquí importa más que en el pasajero: sin posición fresca la política
      // `viajes_difusion_conductores` no le muestra ninguna solicitud.
      if (mounted) {
        setState(() {
          _errorUbicacion = e.message;
          _buscandoUbicacion = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorUbicacion = 'No pudimos leer tu ubicación.';
          _buscandoUbicacion = false;
        });
      }
    }
  }

  void _centrar() {
    final yo = _yo;
    if (yo == null || !_mapaListo) return;
    // El zoom sale del margen de error: no tiene sentido acercarse a nivel de
    // calle si la posición viene de la IP y falla por kilómetros.
    final zoom = yo.precision > 2000
        ? 11.0
        : yo.precision > 500
            ? 13.5
            : 15.5;
    _mapa.move(yo.punto, zoom);
  }

  Future<void> _cambiarDisponibilidad(bool valor) async {
    setState(() => _cambiando = true);
    try {
      await RideService.instance.cambiarDisponibilidad(valor);
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _cambiando = false);
    }
  }

  Timer? _latido;

  /// Mientras el chofer está en línea, la app reporta su posición cada minuto.
  ///
  /// No es un adorno: la política `viajes_difusion_conductores` solo le muestra
  /// solicitudes si tiene una posición de los últimos 10 minutos. Sin este
  /// latido, se pondría «en línea» y no le llegaría ningún viaje.
  void _ajustarLatido() {
    final debeReportar = _estado.disponible && _estado.puedeTrabajar;

    if (!debeReportar) {
      _latido?.cancel();
      _latido = null;
      return;
    }
    if (_latido != null) return;

    _reportarPosicion();
    _latido = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _reportarPosicion(),
    );
  }

  Future<void> _reportarPosicion() async {
    try {
      final pos = await LocationService.instance.posicionActual();
      await RideService.instance.reportarPosicion(
        pos.lat,
        pos.lng,
        _activo?.id,
      );
      // El latido ya tiene la posición fresca: aprovecharla para el punto azul
      // evita pedirle al GPS lo mismo dos veces.
      if (mounted) {
        setState(() {
          _yo = (punto: LatLng(pos.lat, pos.lng), precision: pos.precision);
          _buscandoUbicacion = false;
          _errorUbicacion = null;
        });
      }
    } catch (_) {
      // Si el GPS falla puntualmente no se interrumpe la jornada: el siguiente
      // latido lo reintenta. Lo que sí se nota es que dejan de llegar viajes,
      // y para eso está el aviso de la pantalla.
    }
  }

  Future<void> _abrirPerfil() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverProfileScreen()),
    );
    await _cargar();
  }

  Future<void> _abrirViajes() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverTripsScreen()),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      appBar: const ViewingAsBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final alto = constraints.maxHeight;

          return NotificationListener<DraggableScrollableNotification>(
            onNotification: (aviso) {
              if (aviso.extent != _hoja) {
                setState(() => _hoja = aviso.extent);
              }
              return false;
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: RideMap(
                    centro: _yo?.punto ?? MapDefaults.centro,
                    zoom: _yo == null
                        ? MapDefaults.zoom
                        : MapDefaults.zoomCalle,
                    controlador: _mapa,
                    miUbicacion: _yo,
                    margenCredito: EdgeInsets.only(bottom: alto * _hoja),
                    onListo: () {
                      _mapaListo = true;
                      _centrar();
                    },
                  ),
                ),
                _BarraFlotante(user: user, disponible: _available),
                if (_yo == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.paddingOf(context).top + 72,
                    child: MapNotice(
                      cargando: _buscandoUbicacion,
                      mensaje: _buscandoUbicacion
                          ? 'Buscando tu ubicación…'
                          : _errorUbicacion ??
                              'Sin ubicación no te llegan solicitudes.',
                      onReintentar: _buscandoUbicacion ? null : _ubicar,
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: alto * _hoja + 16,
                  child: MapRoundButton(
                    icon: Icons.my_location,
                    tooltip: 'Centrar en mi ubicación',
                    onPressed: _yo == null ? _ubicar : _centrar,
                  ),
                ),
                DraggableScrollableSheet(
                  initialChildSize: _hojaInicial,
                  minChildSize: _hojaMinima,
                  maxChildSize: 0.92,
                  snap: true,
                  snapSizes: const [_hojaMinima, _hojaInicial, 0.92],
                  builder: (context, scrollController) => _HojaConductor(
                    controller: scrollController,
                    user: user,
                    estado: _estado,
                    activo: _activo,
                    cambiando: _cambiando,
                    onDisponibilidad: _cambiarDisponibilidad,
                    onAbrirViajes: _abrirViajes,
                    onAbrirPerfil: _abrirPerfil,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const _DriverNavBar(),
    );
  }
}

/// Cuenta y campana flotando sobre el mapa.
class _BarraFlotante extends StatelessWidget {
  const _BarraFlotante({required this.user, required this.disponible});

  final AppUser user;
  final bool disponible;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            MapCapsule(
              child: InkWell(
                onTap: () => showAccountSheet(context, user),
                customBorder: const CircleBorder(),
                child: Tooltip(
                  message: 'Cuenta',
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          fontSize: AppText.small,
                          fontWeight: FontWeight.w800,
                          color: disponible ? ride.success : ride.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            const MapCapsule(
              child: SizedBox(
                width: 48,
                height: 48,
                child: NotificationsBell(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido de la hoja del conductor.
class _HojaConductor extends StatelessWidget {
  const _HojaConductor({
    required this.controller,
    required this.user,
    required this.estado,
    required this.activo,
    required this.cambiando,
    required this.onDisponibilidad,
    required this.onAbrirViajes,
    required this.onAbrirPerfil,
  });

  final ScrollController controller;
  final AppUser user;
  final DriverState estado;
  final Trip? activo;
  final bool cambiando;
  final ValueChanged<bool> onDisponibilidad;
  final VoidCallback onAbrirViajes;
  final VoidCallback onAbrirPerfil;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final viaje = activo;
    final vehiculo = user.vehicle;

    return SheetSurface(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          const SheetHandle(),
          _InterruptorJornada(
            disponible: estado.disponible,
            bloqueado: cambiando || !estado.puedeTrabajar,
            onChanged: onDisponibilidad,
          ),
          if (!estado.puedeTrabajar && estado.motivoBloqueo.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ride.infoSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusField),
                border: Border.all(color: ride.info.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 21, color: ride.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      estado.motivoBloqueo,
                      style: TextStyle(
                        fontSize: AppText.small,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: ride.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (viaje != null) ...[
            const SizedBox(height: 16),
            _ViajeActivo(viaje: viaje, onAbrir: onAbrirViajes),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAbrirViajes,
            icon: const Icon(Icons.list_alt, size: 22),
            label: Text(
              viaje != null ? 'Ver mi viaje' : 'Ver solicitudes de viaje',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAbrirPerfil,
            icon: const Icon(Icons.badge_outlined, size: 21),
            label: Text(
              estado.puedeTrabajar
                  ? 'Mi vehículo y documentos'
                  : 'Completar mi cuenta de chofer',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 20, color: ride.inkMuted),
              const SizedBox(width: 8),
              Text(
                'Zona: Quito Norte',
                style: TextStyle(
                  fontSize: AppText.small,
                  color: ride.inkMuted,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('Cambiar')),
            ],
          ),
          if (vehiculo != null) ...[
            const SizedBox(height: 12),
            RideCard(
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car_outlined,
                    size: 26,
                    color: ride.accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehiculo.summary,
                          style: TextStyle(
                            fontSize: AppText.h3,
                            fontWeight: FontWeight.w700,
                            color: ride.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          vehiculo.plate,
                          style: TextStyle(
                            fontSize: AppText.small,
                            color: ride.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 26),
          Text(
            'Oportunidades para ti',
            style: AppTheme.display(
              AppText.h2,
              color: ride.ink,
              letterSpacing: -0.6,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ordenadas por compatibilidad y retorno',
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
          const SizedBox(height: 16),
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
    );
  }
}

/// El control principal del conductor: entrar y salir de la jornada.
///
/// Ocupa el primer lugar de la hoja y cambia de color con el estado, para que
/// se sepa de un vistazo si están llegando viajes o no.
class _InterruptorJornada extends StatelessWidget {
  const _InterruptorJornada({
    required this.disponible,
    required this.bloqueado,
    required this.onChanged,
  });

  final bool disponible;
  final bool bloqueado;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final color = disponible ? ride.success : ride.inkMuted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ride.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disponible ? 'Estás disponible' : 'No estás disponible',
                  style: TextStyle(
                    fontSize: AppText.h3,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  disponible
                      ? 'Te llegan solicitudes de tu zona.'
                      : 'Actívate para recibir solicitudes.',
                  style: TextStyle(
                    fontSize: AppText.label,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: disponible,
            onChanged: bloqueado ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

/// Tarjeta del viaje en marcha del conductor.
class _ViajeActivo extends StatelessWidget {
  const _ViajeActivo({required this.viaje, required this.onAbrir});

  final Trip viaje;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final color = viaje.status.color;

    return RideCard(
      onTap: onAbrir,
      color: color.withValues(alpha: ride.isDark ? 0.16 : 0.10),
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.local_taxi, size: 23, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  viaje.status.label,
                  style: TextStyle(
                    fontSize: AppText.h3,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Hacia ${viaje.destinoTexto}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 24, color: ride.inkMuted),
        ],
      ),
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
    final ride = context.ride;

    final placeStyle = TextStyle(
      fontSize: AppText.h3,
      fontWeight: FontWeight.w700,
      color: ride.ink,
    );
    final metaStyle = TextStyle(
      fontSize: AppText.small,
      color: ride.inkMuted,
    );

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: ride.accent,
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w800,
                    color: ride.isDark ? const Color(0xFF04121C) : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w700,
                    color: ride.accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: ride.successSoft,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  match,
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w800,
                    color: ride.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Desde'),
                    Text(from, style: placeStyle),
                    const SizedBox(height: 10),
                    _Label('Hasta'),
                    Text(to, style: placeStyle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: ride.successSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusField),
                ),
                child: Column(
                  children: [
                    Text(
                      'Tú ganas',
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: ride.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      earnings,
                      style: AppTheme.display(
                        AppText.h2,
                        color: ride.ink,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: ride.inkMuted),
              const SizedBox(width: 6),
              Text(duration, style: metaStyle),
              const SizedBox(width: 18),
              Icon(Icons.route_outlined, size: 18, color: ride.inkMuted),
              const SizedBox(width: 6),
              Text(distance, style: metaStyle),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () {},
                  child: const Text('Aceptar ruta'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
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
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppText.label,
        fontWeight: FontWeight.w600,
        color: context.ride.inkMuted,
      ),
    );
  }
}

class _DriverNavBar extends StatelessWidget {
  const _DriverNavBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Inicio',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Ganancias',
        ),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          selectedIcon: Icon(Icons.route),
          label: 'Viajes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Cuenta',
        ),
      ],
    );
  }
}
