import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/trip.dart';
import '../../services/location_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// Solicitud de viaje: de dónde sales, a dónde vas y cuánto cuesta.
///
/// El origen sale del GPS del teléfono y el destino del catálogo
/// `public.lugares`. No hay mapa ni geocodificación porque eso exigiría un
/// proveedor externo; con las coordenadas del catálogo el precio se calcula
/// igual, por distancia real.
class RequestTripScreen extends StatefulWidget {
  const RequestTripScreen({super.key});

  @override
  State<RequestTripScreen> createState() => _RequestTripScreenState();
}

class _RequestTripScreenState extends State<RequestTripScreen> {
  final _buscador = TextEditingController();

  List<Place> _lugares = const [];
  Place? _destino;

  ({double lat, double lng})? _origen;
  String _origenTexto = 'Tu ubicación actual';

  Quote? _cotizacion;
  bool _cargando = true;
  bool _ubicando = false;
  bool _cotizando = false;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final lugares = await RideService.instance.lugares();
      if (!mounted) return;
      setState(() {
        _lugares = lugares;
        _cargando = false;
      });
      await _ubicar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar los destinos disponibles.';
        _cargando = false;
      });
    }
  }

  Future<void> _ubicar() async {
    setState(() {
      _ubicando = true;
      _error = null;
    });
    try {
      final pos = await LocationService.instance.posicionActual();
      if (!mounted) return;
      setState(() {
        _origen = pos;
        _origenTexto = 'Tu ubicación actual';
      });
      await _cotizar();
    } on LocationUnavailable catch (e) {
      if (!mounted) return;
      // No es un callejón sin salida: se puede elegir un punto del catálogo
      // como origen.
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No pudimos obtener tu ubicación.');
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  /// Usa un lugar del catálogo como punto de partida.
  ///
  /// Es la salida cuando el GPS no está disponible o la persona no sale desde
  /// donde está ahora.
  Future<void> _elegirOrigenDelCatalogo() async {
    final elegido = await _abrirSelector('¿Desde dónde sales?');
    if (elegido == null || !mounted) return;
    setState(() {
      _origen = (lat: elegido.lat, lng: elegido.lng);
      _origenTexto = elegido.nombre;
      _error = null;
    });
    await _cotizar();
  }

  Future<void> _elegirDestino() async {
    final elegido = await _abrirSelector('¿A dónde vas?');
    if (elegido == null || !mounted) return;
    setState(() => _destino = elegido);
    await _cotizar();
  }

  Future<Place?> _abrirSelector(String titulo) {
    return showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SelectorLugar(titulo: titulo, lugares: _lugares),
    );
  }

  Future<void> _cotizar() async {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null) return;

    setState(() {
      _cotizando = true;
      _cotizacion = null;
    });
    try {
      final q = await RideService.instance.cotizar(
        origenLat: origen.lat,
        origenLng: origen.lng,
        destinoLat: destino.lat,
        destinoLng: destino.lng,
      );
      if (!mounted) return;
      setState(() => _cotizacion = q);
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  Future<void> _confirmar() async {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null || _cotizacion == null) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final id = await RideService.instance.solicitar(
        origenLat: origen.lat,
        origenLng: origen.lng,
        origenTexto: _origenTexto,
        destinoLat: destino.lat,
        destinoLng: destino.lng,
        destinoTexto: destino.nombre,
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  bool get _listo =>
      _origen != null && _destino != null && _cotizacion != null && !_enviando;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir un viaje')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                RideCard(
                  child: Column(
                    children: [
                      _Punto(
                        icono: Icons.my_location,
                        color: AppColors.primary,
                        titulo: 'Origen',
                        valor: _origen == null
                            ? (_ubicando ? 'Buscando tu ubicación…' : 'Sin definir')
                            : _origenTexto,
                        accion: _ubicando ? null : _elegirOrigenDelCatalogo,
                        accionLabel: 'Cambiar',
                      ),
                      const Divider(height: 24),
                      _Punto(
                        icono: Icons.place_outlined,
                        color: AppColors.green,
                        titulo: 'Destino',
                        valor: _destino?.nombre ?? 'Elige a dónde vas',
                        accion: _elegirDestino,
                        accionLabel: _destino == null ? 'Elegir' : 'Cambiar',
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
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
    required this.accion,
    required this.accionLabel,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String valor;
  final VoidCallback? accion;
  final String accionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: accion, child: Text(accionLabel)),
      ],
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

/// Lista de lugares con buscador.
class _SelectorLugar extends StatefulWidget {
  const _SelectorLugar({required this.titulo, required this.lugares});

  final String titulo;
  final List<Place> lugares;

  @override
  State<_SelectorLugar> createState() => _SelectorLugarState();
}

class _SelectorLugarState extends State<_SelectorLugar> {
  final _controlador = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  List<Place> get _visibles {
    if (_filtro.trim().isEmpty) return widget.lugares;
    final q = _filtro.toLowerCase();
    return widget.lugares
        .where((l) =>
            l.nombre.toLowerCase().contains(q) ||
            l.direccion.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controlador,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar lugar…',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visibles.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No encontramos ese lugar en el catálogo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (context, i) {
                        final lugar = visibles[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(
                            lugar.nombre,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            lugar.direccion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onTap: () => Navigator.of(context).pop(lugar),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
