import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth_service.dart';
import 'ride_service.dart';

/// Un mensaje del chat de un viaje.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.viajeId,
    required this.autorId,
    required this.texto,
    required this.fecha,
    this.leidoEn,
  });

  final String id;
  final String viajeId;
  final String autorId;
  final String texto;
  final DateTime fecha;
  final DateTime? leidoEn;

  /// `true` si lo escribí yo. Decide de qué lado de la pantalla va.
  bool get esMio => autorId == AuthService.instance.currentUser?.id;

  bool get leido => leidoEn != null;

  /// «14:32». La hora basta: un chat de viaje dura minutos, no días.
  String get hora =>
      '${fecha.hour.toString().padLeft(2, '0')}:'
      '${fecha.minute.toString().padLeft(2, '0')}';

  factory ChatMessage.fromMap(Map<String, dynamic> row) => ChatMessage(
        id: row['id'] as String,
        viajeId: row['viaje_id'] as String,
        autorId: row['autor_id'] as String,
        texto: row['texto'] as String,
        fecha: DateTime.tryParse(row['fecha'] as String)?.toLocal() ??
            DateTime.now(),
        leidoEn: row['leido_en'] == null
            ? null
            : DateTime.tryParse(row['leido_en'] as String)?.toLocal(),
      );
}

/// El chat entre el pasajero y su chofer.
///
/// Los mensajes cuelgan de un **viaje**, no de las personas. No es una
/// mensajería: es «estoy en la puerta de atrás», «ya salgo», «me dejé la
/// mochila». Fuera de un viaje, dos desconocidos no tienen nada que hablar, y
/// una bandeja abierta entre extraños es una vía de acoso.
///
/// Quién puede leer y escribir lo decide Postgres con las políticas de
/// `public.mensajes`, no esta clase: el cliente se puede manipular.
class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  static const String _columnas = 'id, viaje_id, autor_id, texto, fecha, leido_en';

  /// Los mensajes de un viaje, del más viejo al más nuevo.
  Future<List<ChatMessage>> mensajes(String viajeId) async {
    try {
      final rows = await _client
          .from('mensajes')
          .select(_columnas)
          .eq('viaje_id', viajeId)
          .order('fecha');
      return rows.map(ChatMessage.fromMap).toList();
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Envía un mensaje. Devuelve su id.
  Future<String> enviar(String viajeId, String texto) async {
    try {
      final r = await _client.rpc('enviar_mensaje', params: {
        'p_viaje_id': viajeId,
        'p_texto': texto,
      });
      return r as String;
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Marca como leídos los que me mandaron. Silenciosa: que falle no debe
  /// impedir leer el chat.
  Future<void> marcarLeidos(String viajeId) async {
    try {
      await _client.rpc('marcar_mensajes_leidos', params: {
        'p_viaje_id': viajeId,
      });
    } catch (_) {}
  }

  /// Cuántos mensajes sin leer me han mandado en un viaje.
  ///
  /// Sirve para la burbuja del botón de chat: sin ella, nadie se entera de que
  /// le escribieron hasta que abre la pantalla.
  Future<int> sinLeer(String viajeId) async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return 0;
    try {
      final rows = await _client
          .from('mensajes')
          .select('id')
          .eq('viaje_id', viajeId)
          .neq('autor_id', uid)
          .isFilter('leido_en', null);
      return rows.length;
    } on sb.PostgrestException {
      return 0;
    }
  }

  /// Avisa cuando llega un mensaje nuevo de ese viaje.
  ///
  /// El filtro por `viaje_id` evita despertar a la pantalla por chats de otros
  /// viajes; RLS ya lo impediría, pero así ni siquiera viaja el evento.
  sb.RealtimeChannel escuchar(String viajeId, void Function() alLlegar) {
    final canal = _client
        .channel('chat-$viajeId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'viaje_id',
            value: viajeId,
          ),
          callback: (_) => alLlegar(),
        );
    canal.subscribe();
    return canal;
  }

  Future<void> cerrarCanal(sb.RealtimeChannel canal) async {
    await _client.removeChannel(canal);
  }

  String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('todavia no hay chofer')) {
      return 'Todavía no hay chofer asignado a este viaje.';
    }
    if (m.contains('el chat de este viaje ya se cerro')) {
      return 'El chat de este viaje ya se cerró.';
    }
    if (m.contains('ese viaje no es tuyo') ||
        m.contains('violates row-level security')) {
      return 'No puedes escribir en este chat.';
    }
    if (m.contains('demasiado largo')) {
      return 'El mensaje es demasiado largo.';
    }
    return mensaje;
  }
}
