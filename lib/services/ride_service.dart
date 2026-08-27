import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/trip.dart';
import 'auth_service.dart';

/// Motor de viajes.
///
/// Todo lo que decide algo —el precio, quién se queda con una solicitud, si un
/// viaje puede avanzar— vive en funciones de Postgres, no aquí. Este servicio
/// solo las invoca y transporta el resultado.
///
/// Esa separación es deliberada: el cliente se puede manipular, así que no
/// puede ser quien fije la tarifa ni quien resuelva la carrera entre dos
/// choferes que aceptan el mismo viaje.
class RideService {
  RideService._();

  static final RideService instance = RideService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  static const String _detalle = '''
    id, estado, pasajero_id, conductor_id, tarifa_estimada, tarifa_final,
    fecha_solicitud, fecha_inicio, fecha_fin, tarifa_nombre,
    pasajero_nombre, pasajero_telefono,
    conductor_nombre, conductor_telefono, conductor_calificacion,
    vehiculo_placa, vehiculo_marca, vehiculo_modelo, vehiculo_color,
    origen_lat, origen_lng, origen_texto,
    destino_lat, destino_lng, destino_texto
  ''';

  // ---------------------------------------------------------------------------
  // Catálogo de lugares
  // ---------------------------------------------------------------------------

  /// Destinos disponibles. Reemplaza a la geocodificación, que exigiría un
  /// servicio externo.
  Future<List<Place>> lugares() async {
    final rows = await _client
        .from('lugares')
        .select('id, nombre, direccion, latitud, longitud')
        .eq('activo', true)
        .order('nombre');
    return rows.map(Place.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Pasajero
  // ---------------------------------------------------------------------------

  /// Cotiza antes de confirmar. El monto lo calcula el servidor.
  Future<Quote> cotizar({
    required double origenLat,
    required double origenLng,
    required double destinoLat,
    required double destinoLng,
    String? tarifaId,
  }) async {
    final id = tarifaId ?? await _tarifaPorDefecto();
    final rows = await _client.rpc('cotizar_viaje', params: {
      'p_tarifa_id': id,
      'p_origen_lat': origenLat,
      'p_origen_lng': origenLng,
      'p_destino_lat': destinoLat,
      'p_destino_lng': destinoLng,
    }) as List<dynamic>;

    if (rows.isEmpty) {
      throw const RideException('No pudimos calcular el precio del viaje');
    }
    return Quote.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<String> _tarifaPorDefecto() async {
    final row = await _client
        .from('tarifas')
        .select('id')
        .eq('activo', true)
        .order('tarifa_base')
        .limit(1)
        .maybeSingle();
    if (row == null) throw const RideException('No hay tarifas disponibles');
    return row['id'] as String;
  }

  /// Crea la solicitud. Devuelve el id del viaje.
  Future<String> solicitar({
    required double origenLat,
    required double origenLng,
    required String origenTexto,
    required double destinoLat,
    required double destinoLng,
    required String destinoTexto,
    String? tarifaId,
  }) async {
    return _rpc<String>('solicitar_viaje', {
      'p_origen_lat': origenLat,
      'p_origen_lng': origenLng,
      'p_origen_texto': origenTexto,
      'p_destino_lat': destinoLat,
      'p_destino_lng': destinoLng,
      'p_destino_texto': destinoTexto,
      'p_tarifa_id': tarifaId,
    });
  }

  /// Viaje abierto del usuario actual, si tiene alguno.
  ///
  /// Sirve igual para pasajero y para chofer: RLS ya limita las filas a las
  /// suyas, así que no hace falta preguntar por rol.
  Future<Trip?> viajeActivo() async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return null;

    final rows = await _client
        .from('viajes_detalle')
        .select(_detalle)
        .or('pasajero_id.eq.$uid,conductor_id.eq.$uid')
        .not('estado', 'in', '(FINALIZADO,CANCELADO,SIN_CONDUCTOR)')
        .order('fecha_solicitud', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return Trip.fromMap(rows.first);
  }

  Future<Trip?> porId(String viajeId) async {
    final row = await _client
        .from('viajes_detalle')
        .select(_detalle)
        .eq('id', viajeId)
        .maybeSingle();
    return row == null ? null : Trip.fromMap(row);
  }

  /// Historial del usuario actual, ya cerrado o no.
  Future<List<Trip>> historial({int limite = 20}) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return const [];

    final rows = await _client
        .from('viajes_detalle')
        .select(_detalle)
        .or('pasajero_id.eq.$uid,conductor_id.eq.$uid')
        .order('fecha_solicitud', ascending: false)
        .limit(limite);
    return rows.map(Trip.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Conductor
  // ---------------------------------------------------------------------------

  /// Solicitudes abiertas que este chofer puede tomar.
  ///
  /// La política `viajes_difusion_conductores` es la que decide si las ve: solo
  /// llegan si está aprobado y disponible.
  Future<List<Trip>> solicitudesAbiertas() async {
    final rows = await _client
        .from('viajes_detalle')
        .select(_detalle)
        .eq('estado', 'BUSCANDO_CONDUCTOR')
        .isFilter('conductor_id', null)
        .order('fecha_solicitud');
    return rows.map(Trip.fromMap).toList();
  }

  /// Toma una solicitud. Falla si otro chofer se adelantó.
  Future<void> aceptar(String viajeId) =>
      _rpc<void>('aceptar_viaje', {'p_viaje_id': viajeId});

  /// Pasa al siguiente estado del recorrido.
  Future<TripStatus> avanzar(String viajeId) async {
    final estado = await _rpc<String>('avanzar_viaje', {'p_viaje_id': viajeId});
    return TripStatus.fromId(estado);
  }

  /// Cierra el viaje y deja registrado el cobro.
  Future<double> finalizar(String viajeId) async {
    final total = await _rpc<num>('finalizar_viaje', {'p_viaje_id': viajeId});
    return total.toDouble();
  }

  Future<void> cancelar(String viajeId) =>
      _rpc<void>('cancelar_viaje', {'p_viaje_id': viajeId});

  /// Reporta dónde está el chofer.
  ///
  /// El viaje es opcional a propósito: un chofer en línea sin viaje asignado
  /// también necesita ser localizable, porque la difusión de solicitudes solo
  /// le llega si tiene una posición reciente. Cuando sí hay viaje, además queda
  /// el rastro en `public.ubicaciones`.
  Future<void> reportarPosicion(double lat, double lng, [String? viajeId]) =>
      _rpc<void>('reportar_posicion', {
        'p_lat': lat,
        'p_lng': lng,
        'p_viaje_id': viajeId,
      });

  /// Última posición reportada por el chofer durante un viaje.
  ///
  /// Sale de `public.ubicaciones`, no de `conductores`: RLS deja al pasajero
  /// leer las ubicaciones de su propio viaje, pero no la posición suelta de una
  /// persona. Así el seguimiento solo funciona mientras dura el viaje.
  Future<({double lat, double lng})?> posicionDelChofer(String viajeId) async {
    try {
      final fila = await _client
          .from('ubicaciones')
          .select('latitud, longitud')
          .eq('viaje_id', viajeId)
          .eq('tipo', 'posicion_actual')
          .order('registrado_en', ascending: false)
          .limit(1)
          .maybeSingle();

      if (fila == null) return null;
      return (
        lat: (fila['latitud'] as num).toDouble(),
        lng: (fila['longitud'] as num).toDouble(),
      );
    } on sb.PostgrestException {
      return null;
    }
  }

  /// Pone al chofer en línea o fuera de línea.
  Future<void> cambiarDisponibilidad(bool disponible) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) throw const RideException('Debes iniciar sesión');
    try {
      await _client
          .from('conductores')
          .update({'disponible': disponible}).eq('id', uid);
    } on sb.PostgrestException catch (e) {
      // El CHECK conductores_disponible_requiere_aprobacion es el que rebota
      // si la administración todavía no aprobó la cuenta.
      throw RideException(_traducir(e.message));
    }
  }

  /// Estado del chofer actual: aprobación, disponibilidad y vehículo activo.
  Future<DriverState> estadoConductor() async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return const DriverState.sinCuenta();

    final fila = await _client
        .from('conductores')
        .select('estado_aprobacion, disponible, calificacion_promedio')
        .eq('id', uid)
        .maybeSingle();

    if (fila == null) return const DriverState.sinCuenta();

    final vehiculo = await _client
        .from('vehiculos')
        .select('id')
        .eq('conductor_id', uid)
        .eq('activo', true)
        .maybeSingle();

    return DriverState(
      existe: true,
      aprobado: fila['estado_aprobacion'] == 'aprobado',
      estadoAprobacion: fila['estado_aprobacion'] as String,
      disponible: fila['disponible'] as bool,
      calificacion: (fila['calificacion_promedio'] as num?)?.toDouble(),
      tieneVehiculoActivo: vehiculo != null,
    );
  }

  // ---------------------------------------------------------------------------
  // Calificaciones
  // ---------------------------------------------------------------------------

  /// Califica a la otra parte del viaje.
  ///
  /// El trigger `validar_calificacion()` comprueba que el viaje esté finalizado
  /// y que ambos sean sus participantes; el índice único impide calificar dos
  /// veces el mismo viaje.
  Future<void> calificar({
    required String viajeId,
    required String calificadoId,
    required int puntuacion,
    String? comentario,
  }) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) throw const RideException('Debes iniciar sesión');

    try {
      await _client.from('calificaciones').insert({
        'viaje_id': viajeId,
        'calificador_id': uid,
        'calificado_id': calificadoId,
        'puntuacion': puntuacion,
        'comentario': (comentario ?? '').trim().isEmpty ? null : comentario!.trim(),
      });
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// `true` si el usuario actual ya calificó ese viaje.
  Future<bool> yaCalifico(String viajeId) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return false;
    final fila = await _client
        .from('calificaciones')
        .select('id')
        .eq('viaje_id', viajeId)
        .eq('calificador_id', uid)
        .maybeSingle();
    return fila != null;
  }

  // ---------------------------------------------------------------------------
  // Tiempo real
  // ---------------------------------------------------------------------------

  /// Avisa cuando cambia algo en `viajes`.
  ///
  /// Supabase solo emite las filas que RLS dejaría leer a este usuario, así que
  /// un pasajero no se entera de los viajes ajenos. Se reconsulta la vista
  /// porque el evento trae la fila cruda, sin los datos del chofer ni del auto.
  sb.RealtimeChannel escucharViajes(void Function() alCambiar) {
    final canal = _client.channel('viajes-${DateTime.now().microsecondsSinceEpoch}');
    canal
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'viajes',
          callback: (_) => alCambiar(),
        )
        .subscribe();
    return canal;
  }

  Future<void> cerrarCanal(sb.RealtimeChannel canal) async {
    await _client.removeChannel(canal);
  }

  // ---------------------------------------------------------------------------

  Future<T> _rpc<T>(String nombre, Map<String, dynamic> params) async {
    try {
      final resultado = await _client.rpc(nombre, params: params);
      return resultado as T;
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Los mensajes de las funciones ya vienen en español; esto cubre los que
  /// genera Postgres por su cuenta.
  String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('duplicate key') && m.contains('calificaciones')) {
      return 'Ya calificaste este viaje';
    }
    if (m.contains('conductores_disponible_requiere_aprobacion')) {
      return 'Tu cuenta debe estar aprobada para ponerte en línea';
    }
    if (m.contains('violates row-level security')) {
      return 'No tienes permiso para hacer eso';
    }
    return mensaje;
  }
}

/// Situación del chofer, para saber qué ofrecerle en pantalla.
class DriverState {
  const DriverState({
    required this.existe,
    required this.aprobado,
    required this.estadoAprobacion,
    required this.disponible,
    required this.tieneVehiculoActivo,
    this.calificacion,
  });

  const DriverState.sinCuenta()
      : existe = false,
        aprobado = false,
        estadoAprobacion = 'pendiente',
        disponible = false,
        tieneVehiculoActivo = false,
        calificacion = null;

  final bool existe;
  final bool aprobado;
  final String estadoAprobacion;
  final bool disponible;
  final bool tieneVehiculoActivo;
  final double? calificacion;

  /// Solo puede recibir solicitudes si está aprobado y con un auto en servicio.
  bool get puedeTrabajar => aprobado && tieneVehiculoActivo;

  String get motivoBloqueo {
    if (!existe) return 'Tu cuenta de chofer todavía no está creada.';
    if (estadoAprobacion == 'rechazado') {
      return 'La administración rechazó tu solicitud de chofer.';
    }
    if (!aprobado) {
      return 'La administración todavía no aprueba tu cuenta de chofer.';
    }
    if (!tieneVehiculoActivo) {
      return 'Registra un vehículo y márcalo como activo para recibir viajes.';
    }
    return '';
  }
}

class RideException implements Exception {
  const RideException(this.message);
  final String message;

  @override
  String toString() => message;
}
