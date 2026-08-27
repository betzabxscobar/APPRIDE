import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show CameraFit, MapController;
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../core/map_defaults.dart';
import '../../models/trip.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/places_service.dart';
import '../../services/ride_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_map.dart';
import 'place_picker_screen.dart';

/// Solicitud de viaje: de dónde sales, a dónde vas y cuánto cuesta.
///
/// El origen sale del GPS y el destino se busca en todo el mundo con
/// [GeocodingService], o se elige tocando el mapa. Antes solo se podía escoger
/// de un catálogo de 15 lugares de Guayaquil.
class RequestTripScreen extends StatefulWidget {
  const RequestTripScreen({super.key});

  @override
  State<RequestTripScreen> createState() => _RequestTripScreenState();
}

class _RequestTripScreenState extends State<RequestTripScreen> {
  GeoPlace? _origen;
  GeoPlace? _destino;
  Quote? _cotizacion;

  /// Recorrido real por calles. `null` mientras se calcula o si OSRM falla.
  Ruta? _ruta;

  final MapController _mapa = MapController();
  bool _mapaListo = false;

  bool _ubicando = true;
  bool _cotizando = false;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ubicar();
  }

  /// Punto con el que sesgar la búsqueda de direcciones.
  ///
  /// Si ya hay origen, ese; si no, donde esté la persona. Antes aquí iba `null`
  /// mientras no hubiera origen, así que la primera búsqueda —justo la del
  /// origen— salía sin sesgo y devolvía calles del mismo nombre en otra ciudad
  /// o en otro país.
  ({double lat, double lng})? get _referencia => _origen == null
      ? MapDefaults.referenciaBusqueda
      : (lat: _origen!.lat, lng: _origen!.lng);

  Future<void> _ubicar() async {
    setState(() {
      _ubicando = true;
      _error = null;
    });
    try {
      final pos = await LocationService.instance.posicionActual();
      // Se pregunta qué dirección es, para mostrar el nombre de la calle en
      // vez de unas coordenadas.
      final lugar = await GeocodingService.instance.direccionDe(pos.lat, pos.lng);
      if (!mounted) return;
      setState(() {
        _origen = lugar ??
            GeoPlace(
              nombre: 'Tu ubicación actual',
              direccion: '',
              lat: pos.lat,
              lng: pos.lng,
            );
      });
      await _cotizar();
    } on LocationUnavailable catch (e) {
      // No bloquea: se puede elegir el origen a mano.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos obtener tu ubicación.');
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  Future<void> _elegir({required bool esOrigen}) async {
    final lugar = await Navigator.of(context).push<GeoPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          titulo: esOrigen ? '¿Desde dónde sales?' : '¿A dónde vas?',
          cercaDe: _referencia,
        ),
      ),
    );
    if (lugar == null || !mounted) return;

    setState(() {
      if (esOrigen) {
        _origen = lugar;
      } else {
        _destino = lugar;
      }
      _error = null;
    });
    await _cotizar();
  }

  /// Pide a OSRM el recorrido por calles y encuadra el mapa sobre él.
  ///
  /// Si falla no se avisa: el mapa cae a la recta entre los dos puntos, que
  /// orienta igual aunque no sea el camino real.
  Future<void> _trazarRuta(GeoPlace o, GeoPlace d) async {
    final ruta = await RoutingService.instance.entre(
      LatLng(o.lat, o.lng),
      LatLng(d.lat, d.lng),
    );
    // Mientras se calculaba la ruta puede haberse cambiado el origen o el
    // destino; si pasó, esta respuesta ya no vale.
    if (!mounted || ruta == null || !_sigueVigente(o, d)) return;

    setState(() => _ruta = ruta);
    _encuadrar();

    // Con la distancia real el precio cambia: la línea recta por un factor se
    // queda corta. Se vuelve a cotizar, ahora con el recorrido de verdad.
    await _pedirPrecio(o, d, km: ruta.metros / 1000);
  }

  bool _sigueVigente(GeoPlace o, GeoPlace d) =>
      identical(_origen, o) && identical(_destino, d);

  /// Deja a la vista el recorrido entero, como hacen las apps de viajes: lo que
  /// interesa ver es de dónde a dónde, no un zoom fijo.
  void _encuadrar() {
    final puntos = _ruta?.puntos;
    if (puntos == null || puntos.length < 2 || !_mapaListo) return;

    _mapa.fitCamera(
      CameraFit.coordinates(
        coordinates: puntos,
        padding: const EdgeInsets.all(36),
      ),
    );
  }

  Future<void> _cotizar() async {
    final o = _origen;
    final d = _destino;
    if (o == null || d == null) return;

    setState(() {
      _cotizando = true;
      _cotizacion = null;
      _ruta = null;
    });

    // La ruta se pide en paralelo: así el precio aparece enseguida con la
    // estimación del servidor, y se ajusta solo cuando llega el recorrido.
    unawaited(_trazarRuta(o, d));
    await _pedirPrecio(o, d);
  }

  /// Pide el precio al servidor. Con [km] usa la distancia del recorrido real;
  /// sin ella, el servidor la estima desde la línea recta.
  ///
  /// Mandar los kilómetros no abarata el viaje: el servidor los acota contra la
  /// línea recta, que es el mínimo físico, antes de usarlos.
  Future<void> _pedirPrecio(GeoPlace o, GeoPlace d, {double? km}) async {
    try {
      final q = await RideService.instance.cotizar(
        origenLat: o.lat,
        origenLng: o.lng,
        destinoLat: d.lat,
        destinoLng: d.lng,
        distanciaKm: km,
      );
      if (mounted && _sigueVigente(o, d)) setState(() => _cotizacion = q);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  Future<void> _confirmar() async {
    final o = _origen;
    final d = _destino;
    if (o == null || d == null || _cotizacion == null) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final id = await RideService.instance.solicitar(
        origenLat: o.lat,
        origenLng: o.lng,
        origenTexto: o.completo,
        destinoLat: d.lat,
        destinoLng: d.lng,
        destinoTexto: d.completo,
        // La del recorrido real, si llegó a calcularse: es la que produjo el
        // precio del botón.
        distanciaKm: _ruta == null ? null : _ruta!.metros / 1000,
      );

      // El historial se guarda después de que el viaje existe: si fallara,
      // no debe impedir el viaje.
      await PlacesService.instance.recordar(d);

      if (!mounted) return;
      Navigator.of(context).pop(id);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  bool get _listo =>
      _origen != null && _destino != null && _cotizacion != null && !_enviando;

  @override
  Widget build(BuildContext context) {
    final marcadores = <MapMarker>[
      if (_origen != null) MapMarker.origen(LatLng(_origen!.lat, _origen!.lng)),
      if (_destino != null)
        MapMarker.destino(LatLng(_destino!.lat, _destino!.lng)),
    ];

    final centro = _destino != null
        ? LatLng(_destino!.lat, _destino!.lng)
        : _origen != null
            ? LatLng(_origen!.lat, _origen!.lng)
            : MapDefaults.centro;

    return Scaffold(
      appBar: AppBar(title: const Text('Pedir un viaje')),
      body: Column(
        children: [
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _ubicando && _origen == null
                ? const Center(child: CircularProgressIndicator())
                : RideMap(
                    centro: centro,
                    zoom: marcadores.length == 2 ? 12 : 15,
                    controlador: _mapa,
                    marcadores: marcadores,
                    // El recorrido real si ya llegó; si no, la recta entre los
                    // dos puntos para no dejar el mapa sin nada.
                    ruta: _ruta?.puntos ??
                        (marcadores.length == 2
                            ? [
                                LatLng(_origen!.lat, _origen!.lng),
                                LatLng(_destino!.lat, _destino!.lng),
                              ]
                            : const []),
                    onListo: () {
                      _mapaListo = true;
                      _encuadrar();
                    },
                  ),
                ),
                if (_ruta != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _PildoraRuta(ruta: _ruta!),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                RideCard(
                  child: Column(
                    children: [
                      _Punto(
                        icono: Icons.my_location,
                        color: context.ride.accent,
                        titulo: 'Origen',
                        valor: _origen?.nombre ??
                            (_ubicando ? 'Buscando tu ubicación…' : 'Sin definir'),
                        detalle: _origen?.direccion,
                        onTap: () => _elegir(esOrigen: true),
                      ),
                      const Divider(height: 24),
                      _Punto(
                        icono: Icons.place_outlined,
                        color: context.ride.success,
                        titulo: 'Destino',
                        valor: _destino?.nombre ?? 'Busca a dónde vas',
                        detalle: _destino?.direccion,
                        onTap: () => _elegir(esOrigen: false),
                      ),
                    ],
                  ),
                ),
                if (_origen == null && !_ubicando) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _ubicar,
                    icon: const Icon(Icons.gps_fixed, size: 18),
                    label: const Text('Usar mi ubicación actual'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 16),
                if (_cotizando)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_cotizacion != null)
                  _ResumenCotizacion(cotizacion: _cotizacion!),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _listo ? _confirmar : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    _enviando
                        ? 'Pidiendo tu viaje…'
                        : _cotizacion == null
                            ? 'Elige origen y destino'
                            : 'Confirmar por \$${_cotizacion!.total.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'El precio se calcula en el servidor con la tarifa vigente '
                  'y la distancia del recorrido.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: context.ride.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
    required this.detalle,
    required this.onTap,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String valor;
  final String? detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: context.ride.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.ride.ink,
                    ),
                  ),
                  if (detalle != null && detalle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      detalle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.ride.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: context.ride.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _ResumenCotizacion extends StatelessWidget {
  const _ResumenCotizacion({required this.cotizacion});

  final Quote cotizacion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.ride.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        children: [
          Text(
            '\$${cotizacion.total.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: context.ride.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cotizacion.tarifaNombre,
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              color: context.ride.accent,
            ),
          ),
          if (cotizacion.aplicoMinima) ...[
            const SizedBox(height: 6),
            Text(
              'Carrera mínima',
              style: TextStyle(
                fontSize: AppText.micro,
                color: context.ride.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Dato(
                icono: Icons.straighten,
                valor: '${cotizacion.km.toStringAsFixed(1)} km',
                etiqueta: 'Distancia',
              ),
              _Dato(
                icono: Icons.schedule,
                valor: '${cotizacion.minutos} min',
                etiqueta: 'Estimado',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.valor,
    required this.etiqueta,
  });

  final IconData icono;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icono, size: 18, color: context.ride.inkMuted),
        const SizedBox(height: 5),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: context.ride.ink,
          ),
        ),
        Text(
          etiqueta,
          style: TextStyle(fontSize: 10, color: context.ride.inkMuted),
        ),
      ],
    );
  }
}


/// Distancia y tiempo del recorrido real, sobre el mapa.
///
/// No es lo mismo que los kilómetros de la tarifa: el precio lo calcula
/// Postgres a partir de la distancia en línea recta por un factor, mientras que
/// esto es el camino que se va a recorrer de verdad. Se muestran los dos a
/// propósito, cada uno donde le toca.
class _PildoraRuta extends StatelessWidget {
  const _PildoraRuta({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: ride.border),
        boxShadow: [
          BoxShadow(
            color: ride.shadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_outlined, size: 17, color: ride.accent),
          const SizedBox(width: 7),
          Text(
            '${ruta.distanciaTexto} · ${ruta.duracionTexto}',
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              color: ride.ink,
            ),
          ),
        ],
      ),
    );
  }
}
