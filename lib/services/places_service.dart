import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth_service.dart';
import 'geocoding_service.dart';
import 'ride_service.dart';

/// Dirección que la persona ya usó o marcó como favorita.
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.favorita,
    this.etiqueta,
  });

  final String id;
  final String direccion;
  final double lat;
  final double lng;
  final bool favorita;

  /// Nombre corto que le puso la persona: «Casa», «Trabajo».
  final String? etiqueta;

  factory SavedPlace.fromMap(Map<String, dynamic> row) => SavedPlace(
        id: row['id'] as String,
        direccion: row['direccion'] as String,
        lat: (row['latitud'] as num).toDouble(),
        lng: (row['longitud'] as num).toDouble(),
        favorita: row['favorita'] as bool,
        etiqueta: row['etiqueta'] as String?,
      );
}

/// Direcciones propias y catálogo de la ciudad.
///
/// Complementa a [GeocodingService]: la búsqueda mundial resuelve cualquier
/// dirección, pero la mayoría de los viajes van a los mismos tres o cuatro
/// sitios. Tenerlos a mano evita salir a la red y ahorra escribir.
class PlacesService {
  PlacesService._();

  static final PlacesService instance = PlacesService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Favoritas primero, luego las más recientes.
  Future<List<SavedPlace>> guardadas({int limite = 8}) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return const [];

    try {
      final rows = await _client
          .from('direcciones_guardadas')
          .select('id, etiqueta, direccion, latitud, longitud, favorita')
          .eq('usuario_id', uid)
          .order('favorita', ascending: false)
          .order('usada_en', ascending: false)
          .limit(limite);
      return rows.map(SavedPlace.fromMap).toList();
    } catch (_) {
      // Sin conexión el buscador sigue sirviendo: esto son solo atajos.
      return const [];
    }
  }

  /// Catálogo curado de la ciudad, como sugerencia rápida.
  Future<List<GeoPlace>> catalogo({int limite = 12}) async {
    try {
      final rows = await _client
          .from('lugares')
          .select('nombre, direccion, latitud, longitud')
          .eq('activo', true)
          .order('nombre')
          .limit(limite);
      return rows
          .map((r) => GeoPlace(
                nombre: r['nombre'] as String,
                direccion: r['direccion'] as String,
                lat: (r['latitud'] as num).toDouble(),
                lng: (r['longitud'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Deja constancia de que se usó una dirección.
  ///
  /// Si ya existía solo actualiza la fecha, así el historial se ordena por uso
  /// real sin que nadie tenga que guardar nada a mano.
  Future<void> recordar(GeoPlace lugar, {String? etiqueta}) async {
    try {
      await _client.rpc('recordar_direccion', params: {
        'p_direccion': lugar.completo,
        'p_lat': lugar.lat,
        'p_lng': lugar.lng,
        'p_etiqueta': etiqueta,
      });
    } on sb.PostgrestException {
      // Que falle el historial no debe impedir pedir el viaje.
    }
  }

  Future<void> olvidar(String id) async {
    try {
      await _client.from('direcciones_guardadas').delete().eq('id', id);
    } on sb.PostgrestException catch (e) {
      throw RideException(e.message);
    }
  }

  /// Recorta el historial dejando las favoritas y las últimas usadas.
  Future<void> limpiarViejas({int conservar = 10}) async {
    try {
      await _client.rpc('limpiar_direcciones_viejas',
          params: {'p_conservar': conservar});
    } on sb.PostgrestException {
      // Es mantenimiento: si falla, no afecta a nada visible.
    }
  }
}
