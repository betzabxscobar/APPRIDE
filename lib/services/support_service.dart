import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/support_ticket.dart';
import 'auth_service.dart';
import 'ride_service.dart';

/// Casos de soporte: los abre quien usa la app, los responde la
/// administración.
///
/// Quién ve qué lo decide Postgres: cada quien lee los suyos y la
/// administración los lee todos. Responder es solo de administración, y el
/// autor no puede editar su caso — si pudiera, podría cambiar el asunto
/// después de que le respondieran y dejar la respuesta sin sentido.
class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  static const String _columnas =
      'id, usuario_id, viaje_id, categoria, asunto, mensaje, estado, '
      'respuesta, respondido_en, created_at';

  /// Mis casos, del más nuevo al más viejo.
  Future<List<SupportTicket>> mios() async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return const [];

    try {
      final rows = await _client
          .from('tickets_soporte')
          .select(_columnas)
          .eq('usuario_id', uid)
          .order('created_at', ascending: false);
      return rows.map(SupportTicket.fromMap).toList();
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Todos los casos, para la administración.
  ///
  /// Trae también quién los abrió: en una bandeja de soporte, un caso sin
  /// nombre no se puede atender.
  Future<List<SupportTicket>> todos({TicketStatus? estado}) async {
    try {
      var consulta = _client
          .from('tickets_soporte')
          .select('$_columnas, profiles!tickets_soporte_usuario_id_fkey('
              'full_name, email)');

      if (estado != null) consulta = consulta.eq('estado', estado.id);

      // Los que llevan más esperando, primero: es una cola, no un muro.
      final rows = await consulta.order('created_at', ascending: true);
      return rows.map(SupportTicket.fromMap).toList();
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Abre un caso. Devuelve su id.
  Future<String> abrir({
    required String asunto,
    required String mensaje,
    TicketCategory categoria = TicketCategory.otro,
    String? viajeId,
  }) async {
    try {
      final r = await _client.rpc('abrir_ticket', params: {
        'p_asunto': asunto,
        'p_mensaje': mensaje,
        'p_categoria': categoria.id,
        'p_viaje_id': viajeId,
      });
      return r as String;
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  /// Responde y cambia el estado. Solo administración.
  Future<void> responder({
    required String ticketId,
    required String respuesta,
    TicketStatus estado = TicketStatus.resuelto,
  }) async {
    try {
      await _client.rpc('responder_ticket', params: {
        'p_ticket_id': ticketId,
        'p_respuesta': respuesta,
        'p_estado': estado.id,
      });
    } on sb.PostgrestException catch (e) {
      throw RideException(_traducir(e.message));
    }
  }

  String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('escribe un asunto')) return 'Escribe un asunto.';
    if (m.contains('cuentanos un poco mas')) {
      return 'Cuéntanos un poco más para poder ayudarte.';
    }
    if (m.contains('ya tienes 5 casos')) {
      return 'Ya tienes 5 casos abiertos. Espera a que te respondamos.';
    }
    if (m.contains('ese viaje no es tuyo')) {
      return 'Ese viaje no es tuyo.';
    }
    if (m.contains('solo la administracion')) {
      return 'Solo la administración puede responder casos.';
    }
    if (m.contains('violates row-level security')) {
      return 'No tienes permiso para hacer eso.';
    }
    return mensaje;
  }
}
