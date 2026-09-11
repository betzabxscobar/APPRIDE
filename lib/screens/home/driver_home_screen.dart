import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart' show Distance, LatLng, LengthUnit;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_theme.dart';
import '../../core/map_defaults.dart';
import '../../core/ride_colors.dart';
import '../../models/app_user.dart';
import '../../models/fleet.dart';
import '../../models/trip.dart';
import '../../models/user_role.dart';
import '../../screens/driver/driver_profile_screen.dart';
import '../../screens/driver/earnings_screen.dart';
import '../../screens/driver/subscription_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/trips/trip_history_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/trips/driver_trips_screen.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/ride_service.dart';
import '../../services/trip_session_store.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/zone_picker_sheet.dart';
import 'account_sheet.dart';

/// Home del rol conductor.
///
/// Mismo patrón que la pantalla del pasajero: el mapa de fondo y una hoja
/// arrastrable con el estado, los accesos y las oportunidades. Para quien
/// conduce el mapa no es decoración: es dónde está y qué tiene alrededor.
///
/// Las oportunidades son las solicitudes abiertas de verdad, filtradas por la
/// base: solo llegan las que salen de una zona que el chofer trabaja y en la
/// que está ahora mismo.
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

  /// Las solicitudes abiertas que le corresponden. Quién entra aquí lo decide
  /// la política de difusión de la base, no esta pantalla.
  List<Trip> _oportunidades = const [];

  /// Las que el chofer omitió a mano. Solo mientras la pantalla viva: no es una
  /// decisión que valga la pena guardar, y si el viaje sigue abierto dentro de
  /// un rato conviene volver a ofrecérselo.
  final Set<String> _omitidas = {};

  List<WorkZone> _zonas = const [];

  /// Dónde está el chofer y con cuánto margen de error.
  ({LatLng punto, double precision})? _yo;

  bool _buscandoUbicacion = true;
  String? _errorUbicacion;
  bool _mapaListo = false;
  double _hoja = _hojaInicial;

  /// Si ya se reabrió solo el viaje que estaba en marcha. Una sola vez: si el
  /// chofer sale a propósito de la pantalla del viaje, no se le vuelve a
  /// meter dentro.
  bool _reabierto = false;

  /// Refleja el estado real guardado en `public.conductores`, no una bandera
  /// local: antes el interruptor cambiaba de color sin que el servidor se
  /// enterara, así que la pantalla mentía.
  bool get _available => _estado.disponible;

  @override
  void initState() {
    super.initState();
    // Lo último que se supo del viaje, para que la tarjeta esté desde el
    // primer frame en vez de aparecer cuando conteste el servidor.
    _activo = TripSessionStore.instance.cacheado;
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
    LocationService.instance.seguirEnSegundoPlano('en_linea', false);
    final canal = _canal;
    if (canal != null) RideService.instance.cerrarCanal(canal);
    super.dispose();
  }

  /// Abre el selector de zonas y guarda lo que elija.
  Future<void> _elegirZonas() async {
    final elegidas = await mostrarSelectorDeZonas(context, zonas: _zonas);
    if (elegidas == null) return;
    try {
      await RideService.instance.elegirMisZonas(elegidas);
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Toma la solicitud. Puede fallar si otro chofer se adelantó.
  Future<void> _aceptar(Trip viaje) async {
    try {
      await RideService.instance.aceptar(viaje.id);
      await _cargar();
      if (!mounted) return;
      _abrirViajes();
    } on RideException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      await _cargar();
    }
  }

  /// Las que se le enseñan: las abiertas menos las que omitió, y las más
  /// cercanas primero. La cercanía es al punto de recogida, que es el trayecto
  /// que hace de gratis.
  List<Trip> get _oportunidadesVisibles {
    final yo = _yo?.punto;
    final lista = _oportunidades
        .where((v) => !_omitidas.contains(v.id))
        .toList();
    if (yo != null) {
      lista.sort((a, b) {
        final da = _kmHasta(yo, a) ?? double.infinity;
        final db = _kmHasta(yo, b) ?? double.infinity;
        return da.compareTo(db);
      });
    }
    return lista;
  }

  /// Kilómetros en línea recta de donde está el chofer al punto de recogida.
  double? _kmHasta(LatLng yo, Trip viaje) {
    final lat = viaje.origenLat;
    final lng = viaje.origenLng;
    if (lat == null || lng == null) return null;
    return const Distance().as(
      LengthUnit.Kilometer,
      yo,
      LatLng(lat, lng),
    );
  }

  Future<void> _cargar() async {
    try {
      // Un superadministrador entra a conducir sin esperar a que alguien
      // apruebe su propia cuenta: esto se la deja lista antes de leer su
      // estado. El servidor comprueba el rol, así que a nadie más le sirve.
      if (AuthService.instance.currentUser?.role == UserRole.superadmin) {
        await RideService.instance.prepararChoferSuperadmin();
      }

      final estado = await RideService.instance.estadoConductor();
      final activo = await RideService.instance.viajeActivo();

      // Las oportunidades y las zonas no pueden tumbar la pantalla: si fallan
      // se queda con lo que hubiera, que es mejor que un home en rojo.
      List<Trip> oportunidades = _oportunidades;
      List<WorkZone> zonas = _zonas;
      try {
        oportunidades = await RideService.instance.solicitudesAbiertas();
      } catch (_) {}
      try {
        zonas = await RideService.instance.misZonas();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _estado = estado;
          _activo = activo;
          _oportunidades = oportunidades;
          _zonas = zonas;
        });
        _ajustarLatido();
        await TripSessionStore.instance.guardar(activo);
        _reabrirViaje(activo);
      }
    } catch (_) {
      // Sin conexión la pantalla sigue usable. Si había un viaje guardado del
      // arranque, igual se reabre: es cuando más falta hace.
      _reabrirViaje(_activo);
    }
  }

  /// Vuelve a la pantalla del viaje que quedó a medias.
  ///
  /// Cerrar la app en mitad de una carrera dejaba al chofer en el mapa de
  /// inicio, sin la ruta ni los botones para avanzar el viaje. El viaje seguía
  /// en Postgres; lo que faltaba era el camino de vuelta.
  void _reabrirViaje(Trip? viaje) {
    if (_reabierto || viaje == null || !viaje.status.esActivo) return;
    _reabierto = true;

    // Después del frame: `_cargar` corre desde `initState` y desde Realtime, y
    // navegar mientras se construye la pantalla lanza excepción.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _abrirViajes();
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
    LocationService.instance.seguirEnSegundoPlano('en_linea', debeReportar);

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

  /// A dónde lleva cada pestaña de la barra inferior.
  ///
  /// Hasta ahora ninguna llevaba a ningún sitio: la barra no tenía
  /// `onDestinationSelected`. «Ganancias» era el caso más llamativo — un chofer
  /// entra a mirar cuánto lleva hecho y no pasaba nada.
  Future<void> _irA(int indice) async {
    final destino = switch (indice) {
      1 => const EarningsScreen(),
      2 => const TripHistoryScreen(),
      3 => const SettingsScreen(),
      _ => null,
    };
    if (destino == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => destino),
    );
    await _cargar();
  }

  Future<void> _abrirViajes() async {
    // Abrir la pantalla del viaje cuenta como reabrirlo, se llegue por donde
    // se llegue. Sin esto, salir de ella con el viaje aun vivo hacia que
    // `_cargar` volviera a meter dentro al chofer una y otra vez.
    _reabierto = true;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverTripsScreen()),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
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
                    zonasElegidas:
                        _zonas.where((z) => z.elegida).toList(),
                    onCambiarZona: _elegirZonas,
                    oportunidades: _oportunidadesVisibles,
                    kmHasta: (viaje) {
                      final yo = _yo?.punto;
                      return yo == null ? null : _kmHasta(yo, viaje);
                    },
                    onAceptar: _aceptar,
                    onOmitir: (viaje) =>
                        setState(() => _omitidas.add(viaje.id)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _DriverNavBar(onIr: _irA),
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
                  message: 'Cuenta y configuración',
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: UserAvatar(
                        iniciales: user.initials,
                        fotoUrl: user.fotoUrl,
                        radio: 24,
                        // Verde en línea, gris fuera: el color del avatar es
                        // lo que dice de un vistazo si está trabajando.
                        color: disponible ? ride.success : ride.inkMuted,
                        // Sin fondo propio: la cápsula del mapa ya lo pone.
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
    required this.zonasElegidas,
    required this.onCambiarZona,
    required this.oportunidades,
    required this.kmHasta,
    required this.onAceptar,
    required this.onOmitir,
  });

  final ScrollController controller;
  final AppUser user;
  final DriverState estado;
  final Trip? activo;
  final bool cambiando;
  final ValueChanged<bool> onDisponibilidad;
  final VoidCallback onAbrirViajes;
  final VoidCallback onAbrirPerfil;

  final List<WorkZone> zonasElegidas;
  final VoidCallback onCambiarZona;
  final List<Trip> oportunidades;
  final double? Function(Trip) kmHasta;
  final ValueChanged<Trip> onAceptar;
  final ValueChanged<Trip> onOmitir;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final viaje = activo;
    final vehiculo = user.vehicle;

    // Un admin entra aquí a revisar la pantalla, no a trabajar: en la base,
    // `validar_disponibilidad_conductor_real()` y `aceptar_viaje` solo admiten
    // 'driver' y 'superadmin'. Sin esto vería «tu cuenta de chofer todavía no
    // está creada», que lo mandaría a completar unos papeles que no le van a
    // servir para nada.
    final soloRevisa = user.role == UserRole.admin;
    final motivoBloqueo = soloRevisa
        ? 'Esta es la vista de chofer, para revisarla. Una cuenta de '
            'administración no puede ponerse en línea ni tomar viajes.'
        : estado.motivoBloqueo;

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
          if (!estado.puedeTrabajar && motivoBloqueo.isNotEmpty) ...[
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
                      motivoBloqueo,
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
            // La cuota es lo único de esta lista que arregla él solo, así que
            // se le pone el camino delante en vez de dejarlo buscándolo.
            if (estado.soloLeFaltaPagar) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SubscriptionScreen(),
                  ),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 21),
                label: Text(
                  estado.suscripcion.caducada
                      ? 'Renovar mi cuota'
                      : 'Pagar mi cuota mensual',
                ),
              ),
            ],
          ],
          // Trabajando, pero se le acaba. Avisar antes es más barato que
          // explicarle luego por qué dejaron de entrarle solicitudes.
          if (estado.puedeTrabajar && estado.suscripcion.porVencer) ...[
            const SizedBox(height: 14),
            _CuotaPorVencer(cuota: estado.suscripcion),
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
              estado.puedeTrabajar || soloRevisa
                  ? 'Mi vehículo y documentos'
                  : 'Completar mi cuenta de chofer',
            ),
          ),
          // Cuando le falta pagar ya tiene el botón grande arriba; repetirlo
          // aquí sería la misma acción dos veces en la misma hoja.
          if (!estado.soloLeFaltaPagar) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SubscriptionScreen(),
                ),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 21),
              label: const Text('Mi cuota mensual'),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 20, color: ride.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zonasElegidas.isEmpty
                      ? 'Sin zona: recibes de toda la ciudad'
                      : 'Zona: ${zonasElegidas.map((z) => z.nombre).join(', ')}',
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: ride.inkMuted,
                  ),
                ),
              ),
              TextButton(onPressed: onCambiarZona, child: const Text('Cambiar')),
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
            oportunidades.isEmpty
                ? 'Aquí aparecen las solicitudes de tu zona'
                : 'Las más cercanas a ti primero',
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
          const SizedBox(height: 16),
          if (oportunidades.isEmpty)
            _SinOportunidades(disponible: estado.disponible)
          else
            for (final (i, viaje) in oportunidades.indexed) ...[
              _OpportunityCard(
                index: i + 1,
                viaje: viaje,
                kmHastaTi: kmHasta(viaje),
                onAceptar: () => onAceptar(viaje),
                onOmitir: () => onOmitir(viaje),
              ),
              const SizedBox(height: 14),
            ],
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
/// «Te quedan 3 días de cuota». Sale mientras todavía puede trabajar.
class _CuotaPorVencer extends StatelessWidget {
  const _CuotaPorVencer({required this.cuota});

  final DriverSubscription cuota;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final dias = cuota.diasRestantes ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ride.dangerSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusField),
            border: Border.all(color: ride.danger.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 21, color: ride.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dias <= 1
                      ? 'Hoy se te acaba la cuota. Renuévala para seguir '
                          'recibiendo viajes.'
                      : 'Te quedan $dias días de cuota. Renuévala para no '
                          'quedarte sin recibir viajes.',
                  style: TextStyle(
                    fontSize: AppText.small,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: ride.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: ride.danger),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Cuando no hay nada que ofrecer. Dice por qué, que es lo útil.
class _SinOportunidades extends StatelessWidget {
  const _SinOportunidades({required this.disponible});

  final bool disponible;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return RideCard(
      child: Column(
        children: [
          Icon(
            disponible ? Icons.search_off : Icons.pause_circle_outline,
            size: 34,
            color: ride.inkFaint,
          ),
          const SizedBox(height: 10),
          Text(
            disponible
                ? 'No hay solicitudes ahora mismo'
                : 'No estás disponible',
            style: TextStyle(
              fontSize: AppText.h3,
              fontWeight: FontWeight.w700,
              color: ride.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            disponible
                ? 'Te avisamos en cuanto alguien pida un viaje en tu zona.'
                : 'Actívate arriba para que te lleguen solicitudes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Una solicitud abierta de verdad, con lo que el chofer necesita para decidir.
///
/// Antes esta tarjeta traía un «92% de compatibilidad» inventado. No se ha
/// sustituido por otro número de adorno: lo que se enseña ahora es la distancia
/// real hasta el punto de recogida, que es el trayecto que hace sin cobrar y lo
/// que de verdad decide si le conviene.
class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.index,
    required this.viaje,
    required this.kmHastaTi,
    required this.onAceptar,
    required this.onOmitir,
  });

  final int index;
  final Trip viaje;

  /// Cuánto tiene que ir a recogerlo. `null` si todavía no se sabe dónde está
  /// el chofer: entonces no se enseña, en vez de poner un cero que engaña.
  final double? kmHastaTi;

  final VoidCallback onAceptar;
  final VoidCallback onOmitir;

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

    final gana = viaje.ganaConductor;
    final km = viaje.distanciaKm;
    final minutos = viaje.minutosEstimados;
    final cerca = kmHastaTi;

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
                  viaje.categoriaNombre ?? 'Viaje',
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w700,
                    color: ride.accent,
                  ),
                ),
              ),
              if (cerca != null)
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
                    'A ${cerca.toStringAsFixed(1)} km de ti',
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
                    Text(viaje.origenTexto, style: placeStyle),
                    const SizedBox(height: 10),
                    _Label('Hasta'),
                    Text(viaje.destinoTexto, style: placeStyle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (gana != null)
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
                        '\$${gana.toStringAsFixed(2)}',
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
              if (minutos != null) ...[
                Icon(Icons.schedule, size: 18, color: ride.inkMuted),
                const SizedBox(width: 6),
                Text('$minutos min', style: metaStyle),
                const SizedBox(width: 18),
              ],
              if (km != null) ...[
                Icon(Icons.route_outlined, size: 18, color: ride.inkMuted),
                const SizedBox(width: 6),
                Text('${km.toStringAsFixed(1)} km', style: metaStyle),
              ],
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
                  onPressed: onAceptar,
                  child: const Text('Aceptar ruta'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: onOmitir,
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
  const _DriverNavBar({required this.onIr});

  final ValueChanged<int> onIr;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      // Inicio siempre marcado: las demás abren una pantalla encima y se
      // vuelve aquí al cerrarla.
      selectedIndex: 0,
      onDestinationSelected: onIr,
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
