import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Saca al teléfono los avisos que hoy solo se veían dentro de la app.
///
/// La tabla `notificaciones` ya se llenaba sola —los triggers del viaje
/// escriben ahí— pero solo se veían al abrir la campana. Esto escucha esa
/// tabla por Realtime y pinta un aviso del sistema, con sonido y banner.
///
/// **Hasta dónde llega.** Funciona con la app abierta y con la app en segundo
/// plano. **No** funciona con la app cerrada del todo, y eso no se puede
/// arreglar desde aquí: en Android el único canal para despertar una app
/// cerrada es FCM, y en iPhone APNs. Es el sistema operativo quien lo impone,
/// no Supabase. Mientras no haya un proyecto de Firebase, un chofer con Ride
/// cerrada no se entera de nada, y conviene decírselo en vez de que lo
/// descubra perdiendo carreras.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  sb.RealtimeChannel? _canal;
  bool _listo = false;

  /// Canal de Android. Uno solo: todos los avisos de Ride son igual de
  /// urgentes para quien los recibe.
  static const _canalAndroid = AndroidNotificationChannel(
    'ride_avisos',
    'Avisos de Ride',
    description: 'Tus viajes, tus pagos y el estado de tu cuenta.',
    importance: Importance.high,
  );

  /// Prepara el plugin y pide permiso. Se puede llamar más de una vez.
  Future<void> preparar() async {
    if (_listo) return;

    const ajustes = InitializationSettings(
      // El icono de la app: no hay uno propio de notificación todavía.
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: ajustes);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_canalAndroid);

    // Android 13 en adelante exige pedirlo; antes se daba por concedido.
    await android?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _listo = true;
  }

  /// Empieza a escuchar los avisos de [usuarioId].
  ///
  /// El filtro por usuario va en el servidor: así ni siquiera viaja el evento
  /// de otro. RLS ya lo impediría, pero es una barrera menos que atravesar.
  Future<void> escuchar(String usuarioId) async {
    await preparar();
    await dejarDeEscuchar();

    final client = sb.Supabase.instance.client;
    final canal = client
        .channel('avisos-$usuarioId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificaciones',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: usuarioId,
          ),
          callback: (payload) => _mostrar(payload.newRecord),
        );
    canal.subscribe();
    _canal = canal;
  }

  /// Al cerrar sesión: este teléfono deja de recibir los avisos de esa cuenta.
  Future<void> dejarDeEscuchar() async {
    final canal = _canal;
    if (canal == null) return;
    _canal = null;
    await sb.Supabase.instance.client.removeChannel(canal);
  }

  Future<void> _mostrar(Map<String, dynamic> fila) async {
    final titulo = (fila['titulo'] as String?)?.trim();
    final mensaje = (fila['mensaje'] as String?)?.trim();
    if (titulo == null || titulo.isEmpty) return;

    // Un id estable por aviso: si Realtime reemite el mismo insert —pasa al
    // reconectar— se reemplaza el aviso en vez de apilar dos iguales.
    final id = (fila['id'] as String?)?.hashCode ?? DateTime.now().millisecond;

    await _plugin.show(
      id: id & 0x7fffffff,
      title: titulo,
      body: mensaje,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canalAndroid.id,
          _canalAndroid.name,
          channelDescription: _canalAndroid.description,
          importance: Importance.high,
          priority: Priority.high,
          // El texto largo no se corta: un motivo de rechazo de papeles no
          // cabe en una línea.
          styleInformation: mensaje == null
              ? null
              : BigTextStyleInformation(mensaje),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// La plataforma tal como la espera `registrar_dispositivo`.
  static String get plataforma {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }
}
