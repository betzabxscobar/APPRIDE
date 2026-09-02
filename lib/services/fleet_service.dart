import 'dart:io';

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
        .order('created_at');
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
        .select('id, tipo_documento, estado, url_archivo, fecha_subida')
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
  Future<void> subirDocumento(DocumentType tipo, File archivo) async {
    final ext = _extension(archivo.path);
    final ruta = '$_uid/${tipo.id}.$ext';

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
    });
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
      final rows = await consulta.order('fecha_registro');
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
  Future<void> revisarDocumento(String documentoId, bool aprobado) =>
      _rpc<void>('revisar_documento', {
        'p_documento_id': documentoId,
        'p_aprobado': aprobado,
      });

  /// Aprueba o rechaza la cuenta de chofer.
  ///
  /// Aprobar exige que los cuatro documentos estén aprobados y que haya al
  /// menos un vehículo; si falta algo, Postgres lo rechaza diciendo qué falta.
  /// Rechazar no exige nada.
  Future<String> revisarConductor(String conductorId, bool aprobado) =>
      _rpc<String>('revisar_conductor', {
        'p_conductor_id': conductorId,
        'p_aprobado': aprobado,
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
