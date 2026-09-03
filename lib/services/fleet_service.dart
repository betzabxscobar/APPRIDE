import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/fleet.dart';
import 'auth_service.dart';
import 'ride_service.dart';

/// Flota, documentos, notificaciones y métodos de pago.
///
/// Igual que [RideService], no decide nada: las reglas viven en funciones de
/// Postgres. Aquí solo se llaman y se traduce el resultado.
class FleetService {
  FleetService._();

  static final FleetService instance = FleetService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  String get _uid {
    final id = AuthService.instance.currentUser?.id;
    if (id == null) throw const RideException('Debes iniciar sesión');
    return id;
  }

  // ---------------------------------------------------------------------------
  // Vehículos
  // ---------------------------------------------------------------------------

  Future<List<FleetVehicle>> misVehiculos() async {
    final rows = await _client
        .from('vehiculos')
        .select('id, placa, marca, modelo, anio, color, activo, categoria')
        .eq('conductor_id', _uid)
        .order('activo', ascending: false)
        // El más antiguo primero: el orden en que los registró.
        .order('created_at', ascending: true);
    return rows.map(FleetVehicle.fromMap).toList();
  }

  /// Registra uno nuevo, o actualiza si se pasa [vehiculoId].
  ///
  /// El primer vehículo queda en servicio automáticamente: un chofer con un
  /// solo auto y ninguno activo no podría aceptar viajes y no entendería por qué.
  Future<String> guardarVehiculo({
    required String placa,
    required String marca,
    required String modelo,
    required int anio,
    String? color,
    String? vehiculoId,
    String categoria = 'estandar',
  }) async {
    return _rpc<String>('registrar_vehiculo', {
      'p_placa': placa,
      'p_marca': marca,
      'p_modelo': modelo,
      'p_anio': anio,
      'p_color': color,
      'p_vehiculo_id': vehiculoId,
      // De qué tipo es: decide qué viajes puede tomar y a qué precio.
      'p_categoria': categoria,
    });
  }

  Future<void> activarVehiculo(String vehiculoId) =>
      _rpc<void>('activar_vehiculo', {'p_vehiculo_id': vehiculoId});

  // ---------------------------------------------------------------------------
  // Documentos
  // ---------------------------------------------------------------------------

  Future<List<DriverDocument>> misDocumentos() async {
    final rows = await _client
        .from('documentos_conductor')
        .select('id, tipo_documento, estado, url_archivo, fecha_subida, '
            'vehiculo_id, numero, caduca_el, motivo_rechazo')
        .eq('conductor_id', _uid);
    return rows.map(DriverDocument.fromMap).toList();
  }

  /// Sube el archivo al bucket privado y registra el documento.
  ///
  /// La ruta empieza por el id del usuario (`<uid>/licencia.jpg`) porque las
  /// políticas de Storage comparan ese primer segmento con `auth.uid()`: es lo
  /// que impide escribir en la carpeta de otro.
  ///
  /// `upsert` reemplaza el archivo anterior en vez de acumular versiones, y la
  /// función de base vuelve a poner el documento en «pendiente».
  Future<void> subirDocumento(
    DocumentType tipo,
    File archivo, {
    String? vehiculoId,
    String? numero,
    DateTime? caducaEl,
  }) async {
    if (tipo.deVehiculo && vehiculoId == null) {
      throw const RideException('Dinos de qué vehículo es ese papel');
    }
    if (tipo.caduca && caducaEl == null) {
      throw const RideException('Ese documento necesita su fecha de caducidad');
    }

    await _comprobarImagen(archivo);

    final ext = _extension(archivo.path);
    // El vehículo va en la ruta: sin eso, la matrícula del segundo auto
    // sobrescribiría el archivo de la del primero, que es exactamente el
    // problema que se acaba de arreglar en la base.
    final ruta = vehiculoId == null
        ? '$_uid/${tipo.id}.$ext'
        : '$_uid/$vehiculoId/${tipo.id}.$ext';

    try {
      await _client.storage.from('documentos').upload(
            ruta,
            archivo,
            fileOptions: const sb.FileOptions(upsert: true),
          );
    } on sb.StorageException catch (e) {
      throw RideException(_traducirStorage(e.message));
    }

    await _rpc<String>('registrar_documento', {
      'p_tipo': tipo.id,
      'p_url': ruta,
      'p_vehiculo_id': vehiculoId,
      'p_numero': numero,
      'p_caduca_el': caducaEl?.toIso8601String().split('T').first,
    });

    // La foto que revisa la administración y la que ve el pasajero son la
    // misma. Tener dos sería pedirle al chofer que suba su cara dos veces, y
    // dejaría la puerta abierta a que le aprueben una y enseñe otra.
    //
    // Que se vea antes de estar aprobada no es un problema: un chofer sin
    // aprobar no puede ponerse en línea, así que ningún pasajero llega a verla.
    if (tipo == DocumentType.fotoPerfil) {
      try {
        await AuthService.instance.cambiarFoto(archivo);
      } catch (_) {
        // El documento ya quedó registrado, que es lo que importa para la
        // revisión. Si el avatar público falla, se reintenta desde Ajustes.
      }
    }
  }

  /// Rechaza antes de subir lo que no se va a poder revisar.
  ///
  /// El bucket ya limita tamaño y tipo, pero eso no distingue una foto legible
  /// de uno de 40x30 píxeles: el tope de arriba no tiene suelo. Una matrícula
  /// que no se puede leer se rechaza igual, solo que tres días después.
  ///
  /// Se mide con [decodeImageFromList] en vez de traer una librería: solo hace
  /// falta el tamaño, y eso ya lo sabe Flutter.
  Future<void> _comprobarImagen(File archivo) async {
    if (_extension(archivo.path) == 'pdf') return;

    final bytes = await archivo.readAsBytes();
    if (bytes.lengthInBytes > _topeArchivo) {
      throw const RideException(
        'La foto pesa más de 5 MB. Vuelve a tomarla con menos resolución.',
      );
    }

    final ui.Image imagen;
    try {
      imagen = await decodeImageFromList(bytes);
    } catch (_) {
      throw const RideException('Ese archivo no es una foto que podamos leer.');
    }
    final ancho = imagen.width;
    final alto = imagen.height;
    imagen.dispose();

    if (ancho < _ladoMinimo || alto < _ladoMinimo) {
      throw RideException(
        'Esa foto es demasiado pequeña ($ancho×$alto). Tiene que medir al '
        'menos $_ladoMinimo píxeles de lado para que se lea.',
      );
    }
  }

  /// Lo mismo que acepta el bucket `documentos`. Repetirlo aquí es para dar el
  /// mensaje antes de gastar la subida, no para sustituirlo.
  static const int _topeArchivo = 5 * 1024 * 1024;

  /// Por debajo de esto no se lee un número de placa ni el de una póliza.
  static const int _ladoMinimo = 600;

  /// Lo que hay registrado hoy de su identidad.
  ///
  /// Se lee directo de `conductores`: RLS ya limita la fila a la suya, y no
  /// hace falta una función para leer cuatro columnas propias.
  Future<DriverIdentity> miIdentidad() async {
    final row = await _client
        .from('conductores')
        .select('cedula, codigo_dactilar, licencia_tipo, licencia_caduca_el')
        .eq('id', _uid)
        .maybeSingle();
    return row == null ? const DriverIdentity() : DriverIdentity.fromMap(row);
  }

  /// Cédula, código dactilar y licencia.
  ///
  /// Los tres los valida Postgres: la cédula con su dígito verificador, el
  /// dactilar con su formato y la licencia contra la lista de la ANT. Aquí no
  /// se comprueba nada por adelantado para no tener dos reglas que se
  /// contradigan.
  Future<void> registrarIdentidad({
    required String cedula,
    required String codigoDactilar,
    required LicenseType licencia,
    required DateTime licenciaCaducaEl,
  }) =>
      _rpc<void>('registrar_identidad_chofer', {
        'p_cedula': cedula,
        'p_codigo_dactilar': codigoDactilar,
        'p_licencia_tipo': licencia.id,
        'p_licencia_caduca_el':
            licenciaCaducaEl.toIso8601String().split('T').first,
      });

  /// Qué le falta al chofer para que le puedan aprobar la cuenta.
  Future<List<String>> papelesQueFaltan() async {
    final r = await _rpc<List<dynamic>>('papeles_que_faltan_chofer', {});
    return [for (final x in r) x as String];
  }

  /// Qué le falta a un vehículo para poder ponerlo en servicio.
  Future<List<String>> papelesQueFaltanDelVehiculo(String vehiculoId) async {
    final r = await _rpc<List<dynamic>>(
      'papeles_que_faltan_vehiculo',
      {'p_vehiculo_id': vehiculoId},
    );
    return [for (final x in r) x as String];
  }

  /// URL temporal para ver un documento del bucket privado.
  ///
  /// Se firma cada vez y dura una hora: el bucket no es público, así que no hay
  /// un enlace permanente que pueda filtrarse.
  Future<String> urlDocumento(String ruta) async {
    return _client.storage.from('documentos').createSignedUrl(ruta, 3600);
  }

  String _extension(String ruta) {
    final punto = ruta.lastIndexOf('.');
    if (punto == -1 || punto == ruta.length - 1) return 'jpg';
    return ruta.substring(punto + 1).toLowerCase();
  }

  // ---------------------------------------------------------------------------
  // Notificaciones
  // ---------------------------------------------------------------------------

  Future<List<AppNotification>> notificaciones({int limite = 50}) async {
    final rows = await _client
        .from('notificaciones')
        .select('id, titulo, mensaje, leida, fecha')
        .eq('usuario_id', _uid)
        .order('fecha', ascending: false)
        .limit(limite);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> sinLeer() async {
    final rows = await _client
        .from('notificaciones')
        .select('id')
        .eq('usuario_id', _uid)
        .eq('leida', false);
    return rows.length;
  }

  Future<void> marcarTodasLeidas() =>
      _rpc<int>('marcar_notificaciones_leidas', {}).then((_) {});

  /// Avisa cuando llega una notificación nueva.
  ///
  /// El filtro por `usuario_id` evita despertar a la app por avisos ajenos;
  /// RLS ya lo impediría, pero así ni siquiera viaja el evento.
  sb.RealtimeChannel escucharNotificaciones(void Function() alLlegar) {
    final canal = _client
        .channel('notif-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificaciones',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: _uid,
          ),
          callback: (_) => alLlegar(),
        );
    canal.subscribe();
    return canal;
  }

  // ---------------------------------------------------------------------------
  // Métodos de pago
  // ---------------------------------------------------------------------------

  Future<List<PaymentMethod>> misMetodosPago() async {
    final rows = await _client
        .from('metodos_pago')
        .select('id, tipo, detalle_tokenizado, predeterminado')
        .eq('pasajero_id', _uid)
        .order('predeterminado', ascending: false);
    return rows.map(PaymentMethod.fromMap).toList();
  }

  /// Registra un método de pago.
  ///
  /// Para tarjeta se guarda el **token de la pasarela**, nunca el número. La
  /// función de base rechaza cualquier cosa con forma de PAN, y esta app no
  /// tiene formulario para pedirlo.
  Future<String> agregarMetodoPago({
    required String tipo,
    String? token,
    bool predeterminado = true,
  }) {
    return _rpc<String>('registrar_metodo_pago', {
      'p_tipo': tipo,
      'p_token': token,
      'p_predeterminado': predeterminado,
    });
  }

  Future<void> elegirPredeterminado(String metodoId) =>
      _rpc<void>('elegir_metodo_predeterminado', {'p_metodo_id': metodoId});

  Future<void> eliminarMetodoPago(String metodoId) async {
    try {
      await _client.from('metodos_pago').delete().eq('id', metodoId);
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  // ---------------------------------------------------------------------------
  // Revisión de conductores (administración)
  //
  // Aquí no hay ninguna comprobación de rol: la vista `conductores_revision`
  // es `security_invoker`, así que un chofer que llamara a esto se vería solo
  // a sí mismo, y `revisar_documento` y `revisar_conductor` rebotan con 42501
  // si quien llama no es administrativo. La pantalla se limita a no ofrecerlo.
  // ---------------------------------------------------------------------------

  /// Conductores con sus documentos y vehículos, para el panel de revisión.
  ///
  /// [estado] filtra por `estado_aprobacion` (`pendiente`, `aprobado`,
  /// `rechazado`); en null llegan todos.
  Future<List<DriverReview>> conductoresParaRevision({String? estado}) async {
    try {
      var consulta = _client.from('conductores_revision').select();
      if (estado != null) consulta = consulta.eq('estado_aprobacion', estado);

      // Los que llevan más esperando primero: en una cola de revisión, lo
      // último que quieres es que alguien se quede al fondo para siempre.
      // Los que llevan más esperando, primero. `order` es descendente
      // por defecto, así que sin esto la cola de revisión iba al revés
      // y el que más esperaba quedaba el último.
      final rows = await consulta.order('fecha_registro', ascending: true);
      return rows.map(DriverReview.fromMap).toList();
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Un solo conductor, para refrescar su ficha sin recargar la lista entera.
  Future<DriverReview?> conductorParaRevision(String conductorId) async {
    try {
      final row = await _client
          .from('conductores_revision')
          .select()
          .eq('id', conductorId)
          .maybeSingle();
      return row == null ? null : DriverReview.fromMap(row);
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Aprueba o rechaza un documento suelto.
  ///
  /// El trigger `documentos_notificar` avisa al chofer del resultado, así que
  /// desde aquí no hay que mandar nada.
  /// Rechazar exige un motivo, y la base lo impone: es lo único que el chofer
  /// va a leer, y sin ello vuelve a subir exactamente el mismo papel.
  Future<void> revisarDocumento(
    String documentoId,
    bool aprobado, {
    String? motivo,
  }) =>
      _rpc<void>('revisar_documento', {
        'p_documento_id': documentoId,
        'p_aprobado': aprobado,
        'p_motivo': motivo,
      });

  /// Aprueba o rechaza la cuenta de chofer.
  ///
  /// Aprobar exige identidad registrada, licencia vigente y del tipo que
  /// corresponde, sus papeles personales aprobados y al menos un vehículo con
  /// todos los suyos al día. Si falta algo, Postgres lo rechaza diciendo qué.
  /// Rechazar exige un motivo.
  Future<String> revisarConductor(
    String conductorId,
    bool aprobado, {
    String? motivo,
  }) =>
      _rpc<String>('revisar_conductor', {
        'p_conductor_id': conductorId,
        'p_aprobado': aprobado,
        'p_motivo': motivo,
      });

  // ---------------------------------------------------------------------------

  Future<T> _rpc<T>(String nombre, Map<String, dynamic> params) async {
    try {
      final r = await _client.rpc(nombre, params: params);
      return r as T;
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('violates row-level security')) {
      return 'No tienes permiso para hacer eso';
    }
    if (m.contains('vehiculos_un_activo_por_conductor')) {
      return 'Ya tienes otro vehículo en servicio';
    }
    if (m.contains('violates foreign key') && m.contains('pagos')) {
      return 'No puedes borrar un método con pagos registrados';
    }
    if (m.contains('solo la administracion')) {
      return 'Solo la administración puede revisar conductores';
    }
    return mensaje;
  }

  String _traducirStorage(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('exceeded the maximum allowed size') || m.contains('too large')) {
      return 'El archivo pesa más de 5 MB. Usa una foto más liviana.';
    }
    if (m.contains('mime type') || m.contains('not allowed')) {
      return 'Formato no admitido. Sube una foto o un PDF.';
    }
    return 'No pudimos subir el archivo. Inténtalo de nuevo.';
  }
}
