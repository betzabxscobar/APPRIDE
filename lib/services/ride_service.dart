import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/trip.dart';
import '../models/vehicle_category.dart';
import 'auth_service.dart';
import 'h3_service.dart';

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
    origen_lat, origen_lng, origen_texto, origen_referencia,
    destino_lat, destino_lng, destino_texto, destino_referencia,
    categoria, categoria_nombre, categoria_icono
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
        // Alfabético de verdad: `order` es descendente por defecto.
        .order('nombre', ascending: true);
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
    double? distanciaKm,
    String? tarifaId,
    String categoria = VehicleCategory.idPorDefecto,
  }) async {
    final List<dynamic> rows;
    try {
      rows = await _rpc<List<dynamic>>('cotizar_viaje', {
      'p_origen_lat': origenLat,
      'p_origen_lng': origenLng,
      'p_destino_lat': destinoLat,
      'p_destino_lng': destinoLng,
      // La distancia de la ruta real, si ya se calculo. El servidor la acota
      // contra la linea recta antes de usarla, asi que mandarla no permite
      // pagar de menos.
      'p_distancia_km': distanciaKm,
      // Normalmente null: la tarifa la elige el servidor por la hora.
      'p_tarifa_id': tarifaId,
        // El tipo de vehículo multiplica el total, mínima incluida.
        'p_categoria': categoria,
      });
    } on RideException {
      rethrow;
    } catch (_) {
      // Sin red, o el servidor devolvió algo que no se esperaba. Antes esto
      // se escapaba sin envolver y llegaba a la pantalla como una excepción
      // cruda de Supabase, que no dice nada y no ofrece reintentar.
      throw const RideException(
        'No pudimos calcular el precio. Revisa tu conexión e inténtalo de nuevo.',
      );
    }

    if (rows.isEmpty) {
      throw const RideException('No pudimos calcular el precio del viaje');
    }
    return Quote.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }


  /// El precio de **cada** tipo de vehículo para el mismo trayecto.
  ///
  /// Una sola llamada en vez de una por categoría, y los números salen del
  /// servidor ya calculados: multiplicarlos aquí por el factor daría cifras
  /// que no cuadran con lo que se cobra, porque el redondeo y la carrera
  /// mínima no son lineales.
  Future<List<CategoryQuote>> cotizarCategorias({
    required double origenLat,
    required double origenLng,
    required double destinoLat,
    required double destinoLng,
    double? distanciaKm,
  }) async {
    final List<dynamic> rows;
    try {
      rows = await _rpc<List<dynamic>>('cotizar_categorias', {
        'p_origen_lat': origenLat,
        'p_origen_lng': origenLng,
        'p_destino_lat': destinoLat,
        'p_destino_lng': destinoLng,
        'p_distancia_km': distanciaKm,
      });
    } on RideException {
      rethrow;
    } catch (_) {
      throw const RideException(
        'No pudimos calcular los precios. Revisa tu conexión e inténtalo de nuevo.',
      );
    }

    return [
      for (final r in rows)
        CategoryQuote.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Los tipos de vehículo disponibles, sin precios.
  ///
  /// Lo usa el formulario del vehículo del chofer, donde no hay trayecto que
  /// cotizar.
  Future<List<VehicleCategory>> categorias() async {
    final rows = await _client
        .from('categorias_vehiculo')
        .select('id, nombre, descripcion, factor, pasajeros, icono, orden')
        .eq('activo', true)
        // Moto, Estándar, Confort, XL — en ese orden, no al revés.
        .order('orden', ascending: true);
    return rows.map(VehicleCategory.fromMap).toList();
  }

  /// Crea la solicitud. Devuelve el id del viaje.
  Future<String> solicitar({
    required double origenLat,
    required double origenLng,
    required String origenTexto,
    required double destinoLat,
    required double destinoLng,
    required String destinoTexto,
    String? origenReferencia,
    String? destinoReferencia,
    double? distanciaKm,
    String? tarifaId,
    String categoria = VehicleCategory.idPorDefecto,
  }) async {
    // El disco de celdas se calcula aquí porque una política RLS no puede
    // generarlo: H3 no existe dentro de Postgres. Si va en null, la difusión
    // cae a PostGIS.
    final h3 = H3Service.instance;
    return _rpc<String>('solicitar_viaje', {
      'p_origen_lat': origenLat,
      'p_origen_lng': origenLng,
      'p_origen_texto': origenTexto,
      'p_destino_lat': destinoLat,
      'p_destino_lng': destinoLng,
      'p_destino_texto': destinoTexto,
      'p_tarifa_id': tarifaId,
      // La misma distancia con la que se calculó el precio que la persona
      // acaba de aceptar. Sin esto el viaje se guardaría con otro importe.
      'p_distancia_km': distanciaKm,
      'p_origen_celda_h3_7': h3.celda(origenLat, origenLng),
      'p_celdas_difusion': h3.disco(origenLat, origenLng),
      // Lo que el pasajero escribió para que le encuentren. La base recorta
      // los espacios y guarda null si viene vacío.
      'p_origen_referencia': origenReferencia,
      'p_destino_referencia': destinoReferencia,
      'p_categoria': categoria,
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
        // La solicitud que lleva más tiempo esperando, primero: quien
        // pidió antes no debe quedarse al fondo de la lista.
        .order('fecha_solicitud', ascending: true);

    final viajes = rows.map(Trip.fromMap).toList();

    // Solo las del tipo de vehículo que conduce.
    //
    // `aceptar_viaje` ya lo rechaza en el servidor, pero enseñarle a un
    // motorizado viajes que piden una van solo sirve para que toque «Aceptar»
    // y se lleve un error. El filtro de verdad está en la base; este es para
    // no ofrecer lo que va a fallar.
    final mia = await categoriaDeMiVehiculo();
    if (mia == null) return viajes;
    return viajes.where((v) => v.categoria == null || v.categoria == mia).toList();
  }

  /// Categoría del vehículo que el chofer tiene en servicio, o `null`.
  Future<String?> categoriaDeMiVehiculo() async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return null;
    try {
      final fila = await _client
          .from('vehiculos')
          .select('categoria')
          .eq('conductor_id', uid)
          .eq('activo', true)
          .maybeSingle();
      return fila?['categoria'] as String?;
    } on sb.PostgrestException {
      return null;
    }
  }

  /// Toma una solicitud. Falla si otro chofer se adelantó.
  Future<void> aceptar(String viajeId) =>
      _rpc<void>('aceptar_viaje', {'p_viaje_id': viajeId});

  /// Pasa al siguiente estado del recorrido.
  ///
  /// El último salto —de «estoy en el punto» a «en curso»— exige el [codigo]
  /// de seis dígitos que el pasajero tiene en su pantalla y le dicta al
  /// chofer. Los pasos anteriores no lo piden: no cobran nada.
  Future<TripStatus> avanzar(String viajeId, {String? codigo}) async {
    final estado = await _rpc<String>('avanzar_viaje', {
      'p_viaje_id': viajeId,
      'p_codigo': codigo,
    });
    return TripStatus.fromId(estado);
  }

  /// El código que el pasajero le tiene que dictar al chofer.
  ///
  /// Devuelve `null` si todavía no existe —el chofer no ha llegado al punto—
  /// o si quien pregunta no es el pasajero de ese viaje. Eso último no lo
  /// decide esta función: la política `codigos_solo_el_pasajero` no le entrega
  /// la fila a nadie más, ni al propio chofer. Por eso el código vive en su
  /// tabla y no en una columna de `viajes`: RLS filtra filas, no columnas.
  Future<String?> codigoDeInicio(String viajeId) async {
    try {
      final fila = await _client
          .from('codigos_viaje')
          .select('codigo')
          .eq('viaje_id', viajeId)
          .maybeSingle();
      return fila?['codigo'] as String?;
    } on sb.PostgrestException {
      return null;
    }
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
  Future<void> reportarPosicion(double lat, double lng, [String? viajeId]) {
    // Las celdas van solo si H3 está disponible. Donde no lo esté quedan en
    // null y la difusión sigue funcionando por radio con PostGIS.
    final h3 = H3Service.instance;
    return _rpc<void>('reportar_posicion', {
      'p_lat': lat,
      'p_lng': lng,
      'p_viaje_id': viajeId,
      'p_celda_h3_7': h3.celda(lat, lng),
      'p_celda_h3_9': h3.celdaZona(lat, lng),
    });
  }

  /// Última posición reportada por el chofer durante un viaje.
  ///
  /// Sale de `public.ubicaciones`, no de `conductores`: RLS deja al pasajero
  /// leer las ubicaciones de su propio viaje, pero no la posición suelta de una
  /// persona. Así el seguimiento solo funciona mientras dura el viaje.
  Future<DriverPosition?> posicionDelChofer(String viajeId) async {
    try {
      final fila = await _client
          .from('ubicaciones')
          .select('latitud, longitud, registrado_en')
          .eq('viaje_id', viajeId)
          .eq('tipo', 'posicion_actual')
          .order('registrado_en', ascending: false)
          .limit(1)
          .maybeSingle();

      if (fila == null) return null;
      return DriverPosition(
        lat: (fila['latitud'] as num).toDouble(),
        lng: (fila['longitud'] as num).toDouble(),
        cuando: DateTime.tryParse(fila['registrado_en'] as String)?.toLocal() ??
            DateTime.now(),
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

  /// Deja lista la cuenta de chofer de un superadministrador.
  ///
  /// Le crea —o le aprueba— su fila en `conductores`, para que pueda probar el
  /// flujo entero sin esperar a que alguien apruebe su propia cuenta. El
  /// servidor comprueba el rol por su cuenta: `preparar_chofer_superadmin`
  /// rebota con 42501 si quien llama no es superadmin, así que llamarla desde
  /// otra cuenta no sirve de nada.
  ///
  /// Sigue haciendo falta un vehículo activo: eso no es un permiso, es que un
  /// viaje no puede arrancar sin auto asignado.
  ///
  /// Es idempotente y silenciosa: si falla, la pantalla sigue funcionando y
  /// simplemente mostrará el bloqueo de siempre.
  Future<void> prepararChoferSuperadmin() async {
    try {
      await _client.rpc('preparar_chofer_superadmin');
    } catch (_) {
      // Sin permiso o sin red: se sigue como un chofer normal.
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

  /// Lo que lleva ganado el chofer, por periodos.
  ///
  /// Lo calcula Postgres, como la tarifa: el dinero no lo puede decir el
  /// teléfono. Y el reparto sale del porcentaje que tenía la tarifa **de cada
  /// viaje**, no del de hoy: si el reparto cambia, los viajes viejos siguen
  /// contando con el suyo.
  Future<Map<String, DriverEarnings>> ganancias() async {
    final filas = await _client.rpc('ganancias_conductor') as List<dynamic>;
    return {
      for (final f in filas.cast<Map<String, dynamic>>())
        f['periodo'] as String: DriverEarnings.fromMap(f),
    };
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
    if (m.contains('el codigo no coincide')) {
      return 'El código no coincide. Pídeselo otra vez al pasajero.';
    }
    if (m.contains('demasiados intentos')) {
      return 'Demasiados intentos fallidos. Pídele al pasajero que cancele '
          'el viaje y lo vuelva a pedir.';
    }
    if (m.contains('no tiene codigo de inicio')) {
      return 'Este viaje todavía no tiene código. Marca primero que llegaste '
          'al punto.';
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

/// Dónde estaba el chofer y **cuándo** se supo.
///
/// La hora no es un adorno. Si el teléfono del chofer se queda sin datos, la
/// última posición se queda congelada y el alfiler sigue ahí, quieto, como si
/// fuera actual. El pasajero espera mirando un auto que en realidad ya no está
/// donde dice. Con la marca de tiempo se puede avisar.
class DriverPosition {
  const DriverPosition({
    required this.lat,
    required this.lng,
    required this.cuando,
  });

  final double lat;
  final double lng;
  final DateTime cuando;

  Duration get antiguedad => DateTime.now().difference(cuando);

  /// El chofer reporta cada 30 segundos. Pasados tres minutos sin noticias, lo
  /// que se ve en el mapa ya no es de fiar.
  bool get esVieja => antiguedad.inMinutes >= 3;

  /// «hace 2 min», «ahora mismo».
  String get cuandoTexto {
    final m = antiguedad.inMinutes;
    if (m < 1) return 'ahora mismo';
    if (m == 1) return 'hace 1 minuto';
    if (m < 60) return 'hace $m minutos';
    final h = antiguedad.inHours;
    return h == 1 ? 'hace 1 hora' : 'hace $h horas';
  }
}

/// Lo ganado en un periodo: hoy, esta semana, este mes o desde siempre.
class DriverEarnings {
  const DriverEarnings({
    required this.viajes,
    required this.bruto,
    required this.ganado,
    required this.comision,
  });

  final int viajes;

  /// Lo que pagaron los pasajeros.
  final double bruto;

  /// Lo que le queda al chofer.
  final double ganado;

  /// Lo que se lleva la app.
  final double comision;

  factory DriverEarnings.fromMap(Map<String, dynamic> row) => DriverEarnings(
        viajes: (row['viajes'] as num?)?.toInt() ?? 0,
        bruto: (row['bruto'] as num?)?.toDouble() ?? 0,
        ganado: (row['ganado'] as num?)?.toDouble() ?? 0,
        comision: (row['comision'] as num?)?.toDouble() ?? 0,
      );
}

class RideException implements Exception {
  const RideException(this.message);
  final String message;

  @override
  String toString() => message;
}
