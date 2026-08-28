import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_theme.dart';
import '../../core/map_defaults.dart';
import '../../core/ride_colors.dart';
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
  const PlacePickerScreen({super.key, required this.titulo, this.cercaDe});

  final String titulo;

  /// Sesga los resultados hacia esta zona. Sin esto, buscar «Avenida Amazonas»
  /// desde Guayaquil devuelve la de Perú.
  final ({double lat, double lng})? cercaDe;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _busqueda = TextEditingController();
  final _foco = FocusNode();
  final _mapa = MapController();

  List<GeoPlace> _resultados = const [];
  List<SavedPlace> _guardadas = const [];
  List<GeoPlace> _sugeridos = const [];

  GeoPlace? _elegido;

  /// Etiqueta que se le va a poner al próximo lugar que se elija.
  ///
  /// Cuando no es nula, la pantalla deja de servir para elegir destino y pasa a
  /// servir para guardar un favorito: se busca la dirección de «Casa» y, al
  /// tocarla, se guarda con ese nombre en vez de devolverla.
  String? _etiquetaPendiente;

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
    _foco.dispose();
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
    final lugar = await GeocodingService.instance.direccionDe(
      punto.latitude,
      punto.longitude,
    );
    if (!mounted) return;

    setState(() {
      // Si el geocodificador no reconoce el punto, se usa igual con sus
      // coordenadas: el viaje puede salir de un descampado sin nombre.
      _elegido =
          lugar ??
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

  Future<void> _confirmar(GeoPlace lugar) async {
    final etiqueta = _etiquetaPendiente;
    if (etiqueta == null) {
      Navigator.of(context).pop(lugar);
      return;
    }

    // Estamos guardando un favorito, no eligiendo destino.
    setState(() => _buscando = true);
    await PlacesService.instance.recordar(lugar, etiqueta: etiqueta);
    if (!mounted) return;

    _busqueda.clear();
    setState(() {
      _etiquetaPendiente = null;
      _resultados = const [];
      _buscando = false;
    });
    await _cargarAtajos();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado como $etiqueta')),
      );
    }
  }

  /// Empieza a guardar un favorito: pide la dirección de [etiqueta].
  void _guardarFavorito(String etiqueta) {
    _busqueda.clear();
    setState(() {
      _etiquetaPendiente = etiqueta;
      _resultados = const [];
      _enMapa = false;
    });
    _foco.requestFocus();
  }

  /// Pregunta cómo se llama el favorito, para los que no son Casa ni Oficina.
  Future<void> _guardarOtro() async {
    final control = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cómo se llama?'),
        content: TextField(
          controller: control,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Gimnasio, casa de mamá…'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(control.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    control.dispose();

    final limpio = nombre?.trim() ?? '';
    if (limpio.isNotEmpty) _guardarFavorito(limpio);
  }

  Future<void> _olvidar(SavedPlace lugar) async {
    await PlacesService.instance.olvidar(lugar.id);
    await _cargarAtajos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se quitó ${lugar.etiqueta ?? lugar.direccion}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sin referencia se usa la última posición conocida; si tampoco la hay,
    // una vista de país. Nunca una ciudad concreta escrita a mano.
    final centro = widget.cercaDe == null
        ? MapDefaults.centro
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
                focusNode: _foco,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _etiquetaPendiente == null
                      ? 'Calle, número, lugar…'
                      : 'Dirección de ${_etiquetaPendiente!}…',
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
          if (_etiquetaPendiente != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _AvisoGuardando(
                etiqueta: _etiquetaPendiente!,
                onCancelar: () => setState(() => _etiquetaPendiente = null),
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
                    guardandoFavorito: _etiquetaPendiente != null,
                    onElegir: _confirmar,
                    onGuardarFavorito: _guardarFavorito,
                    onGuardarOtro: _guardarOtro,
                    onOlvidar: _olvidar,
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
    required this.guardandoFavorito,
    required this.onElegir,
    required this.onGuardarFavorito,
    required this.onGuardarOtro,
    required this.onOlvidar,
  });

  final bool buscando;
  final List<GeoPlace> resultados;
  final List<SavedPlace> guardadas;
  final List<GeoPlace> sugeridos;
  final bool hayTexto;

  /// Mientras se guarda un favorito no se ofrecen los atajos: se está buscando
  /// una dirección concreta, y volver a ofrecer «Casa» no lleva a ningún sitio.
  final bool guardandoFavorito;

  final void Function(GeoPlace) onElegir;
  final void Function(String etiqueta) onGuardarFavorito;
  final VoidCallback onGuardarOtro;
  final void Function(SavedPlace) onOlvidar;

  /// Etiquetas que se ofrecen de entrada. El resto se crean con «Otro».
  static const List<String> _sugeridasFavoritas = ['Casa', 'Oficina'];

  static IconData iconoDe(String? etiqueta) {
    final e = (etiqueta ?? '').toLowerCase();
    if (e.contains('casa') || e.contains('hogar')) return Icons.home_outlined;
    if (e.contains('oficina') || e.contains('trabajo')) {
      return Icons.work_outline;
    }
    return Icons.star_outline;
  }

  GeoPlace _comoGeoPlace(SavedPlace g) => GeoPlace(
        nombre: g.etiqueta ?? g.direccion,
        direccion: g.etiqueta == null ? '' : g.direccion,
        lat: g.lat,
        lng: g.lng,
      );

  @override
  Widget build(BuildContext context) {
    if (buscando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (hayTexto) {
      if (resultados.isEmpty) {
        return const _Mensaje(
          icono: Icons.search_off,
          titulo: 'Sin resultados',
          detalle:
              'Prueba con otra forma de escribirlo, o elige el punto en el mapa.',
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        // Una fila extra al final para el credito del buscador.
        itemCount: resultados.length + 1,
        itemBuilder: (context, i) {
          if (i == resultados.length) return const _CreditoBuscador();

          final r = resultados[i];
          return _Fila(
            icono: Icons.place_outlined,
            color: context.ride.accent,
            titulo: r.nombre,
            detalle: r.direccion.isEmpty ? null : r.direccion,
            onTap: () => onElegir(r),
          );
        },
      );
    }

    // Sin texto: atajos. Lo propio primero.
    final favoritas = guardadas.where((g) => g.favorita).toList();
    final recientes = guardadas.where((g) => !g.favorita).toList();

    if (guardandoFavorito) {
      return const _Mensaje(
        icono: Icons.bookmark_add_outlined,
        titulo: 'Busca la dirección',
        detalle: 'Escríbela arriba y tócala para guardarla con ese nombre.',
      );
    }

    final faltantes = _sugeridasFavoritas
        .where((e) => !favoritas.any(
              (f) => (f.etiqueta ?? '').toLowerCase() == e.toLowerCase(),
            ))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const _Encabezado('Favoritos'),
        for (final f in favoritas)
          _Fila(
            icono: iconoDe(f.etiqueta),
            color: context.ride.accent,
            titulo: f.etiqueta ?? f.direccion,
            detalle: f.etiqueta == null ? null : f.direccion,
            onTap: () => onElegir(_comoGeoPlace(f)),
            accion: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Quitar de favoritos',
              color: context.ride.inkMuted,
              onPressed: () => onOlvidar(f),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in faltantes)
                ActionChip(
                  avatar: Icon(iconoDe(e), size: 18),
                  label: Text('Añadir $e'),
                  onPressed: () => onGuardarFavorito(e),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Otro'),
                onPressed: onGuardarOtro,
              ),
            ],
          ),
        ),
        if (recientes.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _Encabezado('Recientes'),
          for (final g in recientes)
            _Fila(
              icono: Icons.history,
              color: context.ride.inkMuted,
              titulo: g.direccion,
              onTap: () => onElegir(_comoGeoPlace(g)),
            ),
        ],
        // El catálogo de la ciudad está vacío a propósito: sembrarlo con una
        // ciudad fija mandaba a la gente al otro lado del país.
        if (sugeridos.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _Encabezado('Lugares conocidos'),
          for (final s in sugeridos)
            _Fila(
              icono: Icons.place_outlined,
              color: context.ride.inkMuted,
              titulo: s.nombre,
              detalle: s.direccion,
              onTap: () => onElegir(s),
            ),
        ],
        if (favoritas.isEmpty && recientes.isEmpty) ...[
          const SizedBox(height: 24),
          const _Mensaje(
            icono: Icons.search,
            titulo: 'Busca tu destino',
            detalle: 'Escribe una calle, un número o el nombre de un lugar.',
          ),
        ],
      ],
    );
  }
}

/// Aviso de que la pantalla está guardando un favorito, no eligiendo destino.
class _AvisoGuardando extends StatelessWidget {
  const _AvisoGuardando({required this.etiqueta, required this.onCancelar});

  final String etiqueta;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: ride.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(color: ride.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_VistaLista.iconoDe(etiqueta), size: 20, color: ride.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Elige la dirección de $etiqueta',
              style: TextStyle(
                fontSize: AppText.label,
                fontWeight: FontWeight.w700,
                color: ride.ink,
              ),
            ),
          ),
          TextButton(onPressed: onCancelar, child: const Text('Cancelar')),
        ],
      ),
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
          centro: elegido == null ? centro : LatLng(elegido!.lat, elegido!.lng),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.ride.ink,
                      ),
                    ),
                    if (elegido!.direccion.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        elegido!.direccion,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.ride.inkMuted,
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
        color: context.ride.ink.withValues(alpha: 0.82),
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
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: context.ride.inkMuted,
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
    this.detalle,
    required this.onTap,
    this.accion,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? detalle;
  final VoidCallback onTap;

  /// Control opcional a la derecha, como el aspa de quitar un favorito.
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono, size: 20, color: color),
      title: Text(
        titulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppText.small,
          fontWeight: FontWeight.w700,
          color: context.ride.ink,
        ),
      ),
      subtitle: detalle == null
          ? null
          : Text(
              detalle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.micro,
                color: context.ride.inkMuted,
              ),
            ),
      trailing: accion,
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
            Icon(icono, size: 42, color: context.ride.border),
            const SizedBox(height: 14),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.ride.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crédito del buscador de direcciones.
///
/// Photon busca sobre datos de OpenStreetMap, y su licencia obliga a
/// acreditarlos allí donde se muestren.
class _CreditoBuscador extends StatelessWidget {
  const _CreditoBuscador();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(
        'Datos de OpenStreetMap',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: AppText.micro, color: context.ride.inkFaint),
      ),
    );
  }
}
