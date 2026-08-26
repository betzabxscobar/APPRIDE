import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/trip.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/places_service.dart';
import '../../services/ride_service.dart';
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

  bool _ubicando = true;
  bool _cotizando = false;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ubicar();
  }

  ({double lat, double lng})? get _referencia => _origen == null
      ? null
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

  Future<void> _cotizar() async {
    final o = _origen;
    final d = _destino;
    if (o == null || d == null) return;

    setState(() {
      _cotizando = true;
      _cotizacion = null;
    });
    try {
      final q = await RideService.instance.cotizar(
        origenLat: o.lat,
        origenLng: o.lng,
        destinoLat: d.lat,
        destinoLng: d.lng,
      );
      if (mounted) setState(() => _cotizacion = q);
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
            : const LatLng(-2.1709, -79.9224);

    return Scaffold(
      appBar: AppBar(title: const Text('Pedir un viaje')),
      body: Column(
        children: [
          SizedBox(
            height: 210,
            child: _ubicando && _origen == null
                ? const Center(child: CircularProgressIndicator())
                : RideMap(
                    centro: centro,
                    zoom: marcadores.length == 2 ? 12 : 15,
                    marcadores: marcadores,
                    ruta: marcadores.length == 2
                        ? [
                            LatLng(_origen!.lat, _origen!.lng),
                            LatLng(_destino!.lat, _destino!.lng),
                          ]
                        : const [],
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
                        color: AppColors.primary,
                        titulo: 'Origen',
                        valor: _origen?.nombre ??
                            (_ubicando ? 'Buscando tu ubicación…' : 'Sin definir'),
                        detalle: _origen?.direccion,
                        onTap: () => _elegir(esOrigen: true),
                      ),
                      const Divider(height: 24),
                      _Punto(
                        icono: Icons.place_outlined,
                        color: AppColors.green,
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
                const Text(
                  'El precio se calcula en el servidor con la tarifa vigente '
                  'y la distancia del recorrido.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
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
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (detalle != null && detalle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      detalle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.inkMuted),
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        children: [
          Text(
            '\$${cotizacion.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cotizacion.tarifaNombre,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
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
        Icon(icono, size: 18, color: AppColors.inkMuted),
        const SizedBox(height: 5),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 10, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
