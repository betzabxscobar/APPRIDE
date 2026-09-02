import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/fare.dart';
import 'ride_service.dart';

/// Leer y ajustar los precios.
///
/// Escribir aquí es cosa de la administración, y no lo decide esta clase: las
/// políticas `tarifas_admin` y `categorias_admin` rechazan la escritura de
/// cualquier otra cuenta. Si un pasajero llamara a esto, rebotaría.
class FareService {
  FareService._();

  static final FareService instance = FareService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  Future<List<Fare>> tarifas() async {
    try {
      final rows = await _client
          .from('tarifas')
          .select('id, nombre, tarifa_base, costo_por_km, costo_por_minuto, '
              'carrera_minima, porcentaje_conductor, activo, hora_desde, '
              'hora_hasta')
          // La de por defecto primero —`hora_desde` en null— y luego por
          // franja. `order` es descendente por defecto, de ahí el explícito.
          .order('hora_desde', ascending: true, nullsFirst: true);
      return rows.map(Fare.fromMap).toList();
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Cambia los números de una tarifa.
  ///
  /// Valida antes de salir a la red: un precio negativo o un reparto por
  /// encima del 100 % no son un error del servidor, son un dedo que resbaló.
  Future<void> guardarTarifa({
    required String id,
    required double base,
    required double porKm,
    required double minima,
    required double porcentajeConductor,
  }) async {
    if (base < 0 || porKm < 0 || minima < 0) {
      throw const RideException('Los precios no pueden ser negativos.');
    }
    if (porcentajeConductor <= 0 || porcentajeConductor > 1) {
      throw const RideException(
        'El porcentaje del chofer tiene que estar entre 1 y 100.',
      );
    }
    if (minima < base) {
      throw const RideException(
        'La carrera mínima no puede ser menor que el arranque: nunca se '
        'aplicaría.',
      );
    }

    try {
      await _client.from('tarifas').update({
        'tarifa_base': base,
        'costo_por_km': porKm,
        'carrera_minima': minima,
        'porcentaje_conductor': porcentajeConductor,
      }).eq('id', id);
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Cambia el multiplicador de un tipo de vehículo.
  Future<void> guardarFactor({
    required String id,
    required double factor,
  }) async {
    if (factor <= 0 || factor > 5) {
      throw const RideException(
        'El multiplicador tiene que estar entre 0,01 y 5.',
      );
    }

    try {
      await _client
          .from('categorias_vehiculo')
          .update({'factor': factor}).eq('id', id);
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('violates row-level security')) {
      return 'Solo la administración puede cambiar los precios.';
    }
    if (m.contains('violates check constraint')) {
      return 'Ese valor está fuera de lo que acepta la base.';
    }
    return mensaje;
  }
}
