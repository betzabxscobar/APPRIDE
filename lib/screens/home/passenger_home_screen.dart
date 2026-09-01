import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_theme.dart';
import '../../core/map_defaults.dart';
import '../../core/ride_colors.dart';
import '../../models/app_user.dart';
import '../../models/trip.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/payments/payment_methods_screen.dart';
import '../../screens/trips/request_trip_screen.dart';
import '../../screens/trips/trip_tracking_screen.dart';
import '../../services/location_service.dart';
import '../../services/ride_service.dart';
import '../../services/trip_session_store.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/user_avatar.dart';
import 'account_sheet.dart';

/// Home del rol pasajero: punto de entrada para pedir un viaje y seguirlo.
///
/// El mapa ocupa la pantalla entera y todo lo demás vive en una hoja que se
/// arrastra desde abajo. Antes era una lista de tarjetas sobre fondo liso: se
/// leía como una página web y, en una app de viajes, escondía justo lo que la
/// gente espera ver primero, que es dónde está.
class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  static const double _hojaMinima = 0.34;
  static const double _hojaInicial = 0.46;

  final MapController _mapa = MapController();

  sb.RealtimeChannel? _canal;
  Trip? _activo;

  /// Dónde estamos y con cuánto margen de error. `null` mientras no se sepa.
  ({LatLng punto, double precision})? _yo;

  bool _buscandoUbicacion = true;

  /// Por qué no tenemos la ubicación, en palabras que se puedan mostrar.
  String? _errorUbicacion;

  /// Cuánto de la pantalla ocupa la hoja ahora mismo. Solo sirve para que el
  /// botón de centrar viaje pegado a su borde en vez de quedar tapado.
  double _hoja = _hojaInicial;

  /// `MapController.move` revienta si el mapa todavía no está montado.
  bool _mapaListo = false;

  /// Si ya se reabrió solo el viaje que estaba en marcha.
  ///
  /// Una sola vez por sesión de pantalla: si la persona sale a propósito del
  /// seguimiento con el viaje aún vivo, no se le vuelve a meter dentro.
  bool _reabierto = false;

  @override
  void initState() {
    super.initState();
    // Lo último que se supo del viaje. Se pinta ya, sin esperar al servidor.
    _activo = TripSessionStore.instance.cacheado;
    _cargar();
    _ubicar();
    try {
      // Si el chofer cambia el estado del viaje, la tarjeta se actualiza sola.
      _canal = RideService.instance.escucharViajes(_cargar);
    } catch (_) {
      // Si Realtime no arranca, la pantalla sigue en pie con los datos que
      // trae `_cargar`. Sin este try la excepción sale de initState y deja la
      // pantalla en rojo.
    }
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
      if (!mounted) return;
      setState(() => _activo = viaje);
      await TripSessionStore.instance.guardar(viaje);
      _reabrirViaje(viaje);
    } catch (_) {
      // Sin conexión la pantalla sigue usable; el viaje aparece al reintentar.
      // Con un viaje guardado del arranque, igual se reabre: es justo cuando
      // más falta hace no perderlo de vista.
      _reabrirViaje(_activo);
    }
  }

  /// Vuelve al seguimiento del viaje que quedó a medias.
  ///
  /// Antes, cerrar la app durante un viaje equivalía a perderlo: al volver a
  /// abrir aparecía el mapa de inicio y había que acordarse de tocar la
  /// tarjeta. El viaje nunca se perdió —está en Postgres— pero el camino de
  /// vuelta no existía.
  void _reabrirViaje(Trip? viaje) {
    if (_reabierto || viaje == null || !viaje.status.esActivo) return;
    _reabierto = true;

    // Después del frame: `_cargar` corre desde `initState` y desde Realtime, y
    // navegar mientras se construye la pantalla lanza excepción.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _abrirSeguimiento(viaje.id);
    });
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
      // El mensaje ya explica qué falta: el GPS apagado y el permiso denegado
      // se arreglan de formas distintas.
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
    // El zoom sale del margen de error: acercarse a nivel de calle cuando la
    // posición viene de la IP y falla por kilómetros solo engaña.
    final zoom = yo.precision > 2000
        ? 11.0
        : yo.precision > 500
            ? 13.5
            : 15.5;
    _mapa.move(yo.punto, zoom);
  }

  Future<void> _pedirViaje() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RequestTripScreen()),
    );
    if (id == null || !mounted) return;
    await _abrirSeguimiento(id);
  }

  Future<void> _abrirSeguimiento(String viajeId) async {
    // Abrir el seguimiento cuenta como reabrirlo, se llegue por donde se
    // llegue. Sin esto, salir del seguimiento con el viaje aun vivo hacia que
    // `_cargar` volviera a meter dentro a la persona: no habria forma de
    // volver al mapa de inicio.
    _reabierto = true;

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
      appBar: ViewingAsBar.of(context),
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
                    // La atribución de OpenStreetMap tiene que verse: sube
                    // con la hoja, no se queda detrás de ella.
                    margenCredito: EdgeInsets.only(bottom: alto * _hoja),
                    onListo: () {
                      _mapaListo = true;
                      _centrar();
                    },
                  ),
                ),
                _BarraFlotante(user: user),
                if (_yo == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.paddingOf(context).top + 72,
                    child: MapNotice(
                      cargando: _buscandoUbicacion,
                      mensaje: _buscandoUbicacion
                          ? 'Buscando tu ubicación…'
                          : _errorUbicacion ?? 'No sabemos dónde estás.',
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
                  builder: (context, scrollController) => _HojaPasajero(
                    controller: scrollController,
                    user: user,
                    activo: _activo,
                    onPedirViaje: _pedirViaje,
                    onAbrirViaje: () => _abrirSeguimiento(_activo!.id),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const _PassengerNavBar(),
    );
  }
}

/// Controles que flotan sobre el mapa: cuenta a la izquierda, campana a la
/// derecha. Van en cápsulas opacas porque sobre un mapa un icono suelto se
/// pierde en cuanto pasa por encima de una calle clara.
class _BarraFlotante extends StatelessWidget {
  const _BarraFlotante({required this.user});

  final AppUser user;

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
                  message: 'Cuenta y configuración',
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: UserAvatar(
                        iniciales: user.initials,
                        fotoUrl: user.fotoUrl,
                        radio: 24,
                        color: ride.accent,
                        // Sin fondo propio: la cápsula del mapa ya lo pone, y
                        // dos círculos superpuestos se ven como un error.
                        fondo: Colors.transparent,
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

/// Contenido de la hoja del pasajero.
class _HojaPasajero extends StatelessWidget {
  const _HojaPasajero({
    required this.controller,
    required this.user,
    required this.activo,
    required this.onPedirViaje,
    required this.onAbrirViaje,
  });

  final ScrollController controller;
  final AppUser user;
  final Trip? activo;
  final VoidCallback onPedirViaje;
  final VoidCallback onAbrirViaje;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final viaje = activo;

    return SheetSurface(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          const SheetHandle(),
          Text(
            '¡Hola, ${user.firstName}! 👋',
            style: AppTheme.display(
              AppText.h2,
              color: ride.ink,
              letterSpacing: -0.6,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '¿A dónde vamos hoy?',
            style: TextStyle(fontSize: AppText.body, color: ride.inkMuted),
          ),
          const SizedBox(height: 20),
          if (viaje != null) ...[
            _ViajeEnCurso(viaje: viaje, onAbrir: onAbrirViaje),
            const SizedBox(height: 16),
          ] else ...[
            _BuscadorDestino(onTap: onPedirViaje),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onPedirViaje,
              icon: const Icon(Icons.local_taxi, size: 22),
              label: const Text('Pedir un viaje'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PaymentMethodsScreen(),
                ),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 21),
              label: const Text('Métodos de pago'),
            ),
          ],
          const SizedBox(height: 22),
          const _SafePointCard(),
          const SizedBox(height: 26),
          Text(
            'Elige tu prioridad de ruta',
            style: AppTheme.display(
              AppText.h3,
              color: ride.ink,
              letterSpacing: -0.4,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _PriorityCard(
            icon: Icons.bolt,
            color: ride.accent,
            title: 'Más rápido',
            subtitle: 'Llegas antes con la mejor ruta.',
          ),
          const SizedBox(height: 12),
          _PriorityCard(
            icon: Icons.verified_user_outlined,
            color: ride.success,
            title: 'Más seguro',
            subtitle: 'Rutas con mejor historial de seguridad.',
          ),
          const SizedBox(height: 12),
          _PriorityCard(
            icon: Icons.savings_outlined,
            color: ride.info,
            title: 'Más económico',
            subtitle: 'Ahorra más con opciones eficientes.',
          ),
        ],
      ),
    );
  }
}

/// El control principal de la pantalla: la caja de destino.
///
/// Va resaltada con el color de marca porque es la acción que la gente viene a
/// hacer; el resto de la hoja es secundario.
class _BuscadorDestino extends StatelessWidget {
  const _BuscadorDestino({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final radius = BorderRadius.circular(AppTheme.radiusLarge);

    return Material(
      color: ride.accentSoft,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: ride.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              _DestinationRow(
                icon: Icons.place_outlined,
                label: '¿A dónde quieres llegar?',
                destacado: true,
              ),
              Divider(height: 1, color: ride.accent.withValues(alpha: 0.2)),
              const _DestinationRow(
                icon: Icons.my_location,
                label: 'Usar mi ubicación como punto de partida',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.icon,
    required this.label,
    this.destacado = false,
  });

  final IconData icon;
  final String label;

  /// La fila del destino se pinta con más peso que la del origen: es la que
  /// hay que tocar.
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: destacado ? ride.accent : ride.inkMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppText.body,
                fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
                color: destacado ? ride.ink : ride.inkMuted,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 22, color: ride.inkMuted),
        ],
      ),
    );
  }
}

class _SafePointCard extends StatelessWidget {
  const _SafePointCard();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Punto Ride seguro',
                  style: TextStyle(
                    fontSize: AppText.h3,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                  'Verificado',
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w700,
                    color: ride.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Av. Amazonas 1234 y Naciones Unidas\nQuito',
            style: TextStyle(
              fontSize: AppText.small,
              height: 1.45,
              color: ride.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.directions_walk, size: 19, color: ride.inkMuted),
              const SizedBox(width: 7),
              Text(
                '3 min caminando',
                style: TextStyle(
                  fontSize: AppText.small,
                  color: ride.inkMuted,
                ),
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
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: ride.isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusField),
            ),
            child: Icon(icon, size: 25, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppText.h3,
                    fontWeight: FontWeight.w700,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppText.small,
                    height: 1.35,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 22, color: ride.inkMuted),
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
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Inicio',
        ),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          selectedIcon: Icon(Icons.route),
          label: 'Viajes',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Mensajes',
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

/// Tarjeta del viaje en marcha, con acceso directo al seguimiento.
class _ViajeEnCurso extends StatelessWidget {
  const _ViajeEnCurso({required this.viaje, required this.onAbrir});

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
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
          ),
          const SizedBox(width: 16),
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
