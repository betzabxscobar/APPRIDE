import 'package:flutter/material.dart';

/// De qué va un caso de soporte.
enum TicketCategory {
  viaje('viaje', 'Un viaje', Icons.route_outlined),
  pago('pago', 'Un cobro', Icons.payments_outlined),
  cuenta('cuenta', 'Mi cuenta', Icons.person_outline),
  conductor('conductor', 'Ser conductor', Icons.drive_eta_outlined),
  otro('otro', 'Otra cosa', Icons.help_outline);

  const TicketCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static TicketCategory fromId(String? id) => TicketCategory.values.firstWhere(
        (c) => c.id == id,
        orElse: () => TicketCategory.otro,
      );
}

/// En qué punto está el caso.
enum TicketStatus {
  abierto('abierto', 'Abierto'),
  enProceso('en_proceso', 'En proceso'),
  resuelto('resuelto', 'Resuelto'),
  cerrado('cerrado', 'Cerrado');

  const TicketStatus(this.id, this.label);

  final String id;
  final String label;

  bool get esFinal => this == resuelto || this == cerrado;

  static TicketStatus fromId(String? id) => TicketStatus.values.firstWhere(
        (e) => e.id == id,
        orElse: () => TicketStatus.abierto,
      );
}

/// Un caso de soporte.
///
/// Hasta ahora no había ninguna vía: si a alguien le cobraban de más, si un
/// chofer no aparecía o si le rechazaban un documento sin motivo, no tenía a
/// quién decírselo dentro de la app.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.usuarioId,
    required this.categoria,
    required this.asunto,
    required this.mensaje,
    required this.estado,
    required this.creado,
    this.viajeId,
    this.respuesta,
    this.respondidoEn,
    this.autorNombre,
    this.autorCorreo,
  });

  final String id;
  final String usuarioId;

  /// El viaje al que se refiere, si va sobre uno.
  final String? viajeId;

  final TicketCategory categoria;
  final String asunto;
  final String mensaje;
  final TicketStatus estado;
  final DateTime creado;

  final String? respuesta;
  final DateTime? respondidoEn;

  /// Quién lo abrió. Solo llega en la vista de administración.
  final String? autorNombre;
  final String? autorCorreo;

  bool get respondido => (respuesta ?? '').trim().isNotEmpty;

  /// «hace 20 min», «ayer», «12/08/2026».
  String get cuando {
    final d = DateTime.now().difference(creado);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays == 1) return 'ayer';
    if (d.inDays < 7) return 'hace ${d.inDays} días';
    return '${creado.day.toString().padLeft(2, '0')}/'
        '${creado.month.toString().padLeft(2, '0')}/${creado.year}';
  }

  factory SupportTicket.fromMap(Map<String, dynamic> row) {
    // En el panel de administración viene el perfil del autor anidado.
    final perfil = row['profiles'] as Map<String, dynamic>?;

    return SupportTicket(
      id: row['id'] as String,
      usuarioId: row['usuario_id'] as String,
      viajeId: row['viaje_id'] as String?,
      categoria: TicketCategory.fromId(row['categoria'] as String?),
      asunto: row['asunto'] as String,
      mensaje: row['mensaje'] as String,
      estado: TicketStatus.fromId(row['estado'] as String?),
      creado: DateTime.tryParse(row['created_at'] as String)?.toLocal() ??
          DateTime.now(),
      respuesta: row['respuesta'] as String?,
      respondidoEn: row['respondido_en'] == null
          ? null
          : DateTime.tryParse(row['respondido_en'] as String)?.toLocal(),
      autorNombre: perfil?['full_name'] as String?,
      autorCorreo: perfil?['email'] as String?,
    );
  }
}
