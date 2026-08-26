import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_colors.dart';
import '../../services/geocoding_service.dart';
import '../../services/places_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_map.dart';

/// Elegir un punto: buscando la dirección o tocando el mapa.
///
/// Sustituye al catálogo fijo de 15 lugares. Ahora se busca en todo el mundo
/// contra un geocodificador, y el catálogo queda como sugerencia rápida junto a
/// las direcciones que la persona ya usó.
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({
    super.key,
    required this.titulo,
    this.cercaDe,
  });

  final String titulo;

  /// Sesga los resultados hacia esta zona. Sin esto, buscar «Avenida Amazonas»
  /// desde Guayaquil devuelve la de Perú.
  final ({double lat, double lng})? cercaDe;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _busqueda = TextEditingController();
  final _mapa = MapController();

  List<GeoPlace> _resultados = const [];
  List<SavedPlace> _guardadas = const [];
  List<GeoPlace> _sugeridos = const [];

  GeoPlace? _elegido;
  bool _buscando = false;
  bool _enMapa = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarAtajos();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    GeocodingService.instance.cancelarEspera();
    super.dispose();
  }

  Future<void> _cargarAtajos() async {
    final guardadas = await PlacesService.instance.guardadas();
    final catalogo = await PlacesService.instance.catalogo();
    if (!mounted) return;
    setState(() {
      _guardadas = guardadas;
      _sugeridos = catalogo;
    });
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().length < 3) {
      setState(() {
        _resultados = const [];
        _buscando = false;
      });
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
    });

    try {
      final r = await GeocodingService.instance.buscarConEspera(
        texto,
        cercaDe: widget.cercaDe,
      );
      // `null` significa que otra pulsación canceló esta búsqueda.
      if (r == null || !mounted) return;
      setState(() {
        _resultados = r;
        _buscando = false;
      });
    } on GeocodingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _buscando = false;
      });
    }
  }

  /// Al tocar el mapa se pregunta qué dirección es ese punto.
  Future<void> _tocarMapa(LatLng punto) async {
    setState(() => _buscando = true);
    final lugar = await GeocodingService.instance
        .direccionDe(punto.latitude, punto.longitude);
    if (!mounted) return;

    setState(() {
      // Si el geocodificador no reconoce el punto, se usa igual con sus
      // coordenadas: el viaje puede salir de un descampado sin nombre.
      _elegido = lugar ??
          GeoPlace(
            nombre: 'Punto en el mapa',
            direccion:
                '${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)}',
            lat: punto.latitude,
            lng: punto.longitude,
          );
      _buscando = false;
    });
  }

  void _confirmar(GeoPlace lugar) => Navigator.of(context).pop(lugar);

  @override
  Widget build(BuildContext context) {
    final centro = widget.cercaDe == null
        ? const LatLng(-2.1709, -79.9224)
        : LatLng(widget.cercaDe!.lat, widget.cercaDe!.lng);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _enMapa = !_enMapa),
            icon: Icon(_enMapa ? Icons.list : Icons.map_outlined, size: 18),
            label: Text(_enMapa ? 'Buscar' : 'Mapa'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_enMapa)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _busqueda,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Calle, número, lugar…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _busqueda.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _busqueda.clear();
                            _buscar('');
                          },
                        ),
                ),
                onChanged: _buscar,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ErrorBanner(message: _error!),
            ),
          Expanded(
            child: _enMapa
                ? _VistaMapa(
                    centro: centro,
                    controlador: _mapa,
                    elegido: _elegido,
                    buscando: _buscando,
                    onTap: _tocarMapa,
                    onConfirmar: () => _confirmar(_elegido!),
                  )
                : _VistaLista(
                    buscando: _buscando,
                    resultados: _resultados,
                    guardadas: _guardadas,
                    sugeridos: _sugeridos,
                    hayTexto: _busqueda.text.trim().length >= 3,
                    onElegir: _confirmar,
                  ),
          ),
        ],
      ),
    );
  }
}

class _VistaLista extends StatelessWidget {
  const _VistaLista({
    required this.buscando,
    required this.resultados,
    required this.guardadas,
    required this.sugeridos,
    required this.hayTexto,
    required this.onElegir,
  });

  final bool buscando;
  final List<GeoPlace> resultados;
  final List<SavedPlace> guardadas;
  final List<GeoPlace> sugeridos;
  final bool hayTexto;
  final void Function(GeoPlace) onElegir;

  @override
  Widget build(BuildContext context) {
    if (buscando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mientras no se escribe nada se ofrecen atajos: lo propio primero.
    if (!hayTexto) {
      if (guardadas.isEmpty && sugeridos.isEmpty) {
        return const _Mensaje(
          icono: Icons.search,
          titulo: 'Busca tu destino',
          detalle: 'Escribe una calle, un número o el nombre de un lugar.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          if (guardadas.isNotEmpty) ...[
            const _Encabezado('Tus direcciones'),
            for (final g in guardadas)
              _Fila(
                icono: g.favorita ? Icons.star : Icons.history,
                color: g.favorita ? const Color(0xFFF5A623) : AppColors.inkMuted,
                titulo: g.etiqueta ?? g.direccion,
                detalle: g.etiqueta == null ? null : g.direccion,
                onTap: () => onElegir(GeoPlace(
                  nombre: g.etiqueta ?? g.direccion,
                  direccion: g.etiqueta == null ? '' : g.direccion,
                  lat: g.lat,
                  lng: g.lng,
                )),
              ),
            const SizedBox(height: 14),
          ],
          if (sugeridos.isNotEmpty) ...[
            const _Encabezado('Lugares conocidos'),
            for (final s in sugeridos)
              _Fila(
                icono: Icons.place_outlined,
                color: AppColors.inkMuted,
                titulo: s.nombre,
                detalle: s.direccion,
                onTap: () => onElegir(s),
              ),
          ],
        ],
      );
    }

    if (resultados.isEmpty) {
      return const _Mensaje(
        icono: Icons.search_off,
        titulo: 'Sin resultados',
        detalle: 'Prueba con otra forma de escribirlo, o elige el punto en el mapa.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: resultados.length,
      itemBuilder: (context, i) {
        final r = resultados[i];
        return _Fila(
          icono: Icons.place_outlined,
          color: AppColors.primary,
          titulo: r.nombre,
          detalle: r.direccion.isEmpty ? null : r.direccion,
          onTap: () => onElegir(r),
        );
      },
    );
  }
}

class _VistaMapa extends StatelessWidget {
  const _VistaMapa({
    required this.centro,
    required this.controlador,
    required this.elegido,
    required this.buscando,
    required this.onTap,
    required this.onConfirmar,
  });

  final LatLng centro;
  final MapController controlador;
  final GeoPlace? elegido;
  final bool buscando;
  final void Function(LatLng) onTap;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RideMap(
          centro: elegido == null
              ? centro
              : LatLng(elegido!.lat, elegido!.lng),
          controlador: controlador,
          onTap: onTap,
          marcadores: elegido == null
              ? const []
              : [MapMarker.destino(LatLng(elegido!.lat, elegido!.lng))],
        ),
        if (elegido == null && !buscando)
          const Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _Pista('Toca el mapa para elegir el punto'),
          ),
        if (buscando)
          const Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _Pista('Buscando la dirección…'),
          ),
        if (elegido != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      elegido!.nombre,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (elegido!.direccion.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        elegido!.direccion,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: onConfirmar,
                      child: const Text('Usar este punto'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pista extends StatelessWidget {
  const _Pista(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono, size: 20, color: color),
      title: Text(
        titulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      subtitle: detalle == null
          ? null
          : Text(
              detalle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
      onTap: onTap,
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 42, color: AppColors.border),
            const SizedBox(height: 14),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
