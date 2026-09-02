import 'package:flutter/material.dart';

/// Vehículo registrado por un conductor, tal como vive en `public.vehiculos`.
///
/// Distinto de [Vehicle] en `vehicle.dart`, que es el resumen que se muestra en
/// el perfil: este tiene id y sabe si está en servicio.
class FleetVehicle {
  const FleetVehicle({
    required this.id,
    required this.placa,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.activo,
    this.color,
    this.categoria = 'estandar',
  });

  final String id;
  final String placa;
  final String marca;
  final String modelo;
  final int anio;
  final bool activo;
  final String? color;

  /// `moto`, `estandar`, `confort` o `xl`. Decide qué viajes puede tomar.
  final String categoria;

  String get resumen => '$marca $modelo · $anio';

  factory FleetVehicle.fromMap(Map<String, dynamic> row) => FleetVehicle(
        id: row['id'] as String,
        placa: row['placa'] as String,
        marca: row['marca'] as String,
        modelo: row['modelo'] as String,
        anio: (row['anio'] as num).toInt(),
        activo: row['activo'] as bool,
        color: row['color'] as String?,
        categoria: (row['categoria'] as String?) ?? 'estandar',
      );
}

/// Los cuatro documentos que la administración exige para aprobar a un chofer.
///
/// El orden es el de la revisión: primero quién es la persona, después qué le
/// habilita a conducir y por último el vehículo.
enum DocumentType {
  cedula('cedula', 'Cédula de identidad',
      'Foto del frente de tu cédula', Icons.badge_outlined),
  licencia('licencia', 'Licencia de conducir',
      'Foto del frente de tu licencia vigente', Icons.credit_card_outlined),
  soat('SOAT', 'SOAT', 'Póliza del seguro obligatorio',
      Icons.shield_outlined),
  matricula('matricula', 'Matrícula', 'Matrícula del vehículo',
      Icons.description_outlined);

  const DocumentType(this.id, this.label, this.hint, this.icon);

  /// Valor tal como lo espera la base.
  final String id;
  final String label;
  final String hint;
  final IconData icon;

  static DocumentType fromId(String id) => DocumentType.values.firstWhere(
        (d) => d.id == id,
        orElse: () => DocumentType.licencia,
      );
}

/// Estado de revisión de un documento.
enum DocumentStatus {
  pendiente('pendiente', 'En revisión'),
  aprobado('aprobado', 'Aprobado'),
  rechazado('rechazado', 'Rechazado');

  const DocumentStatus(this.id, this.label);
  final String id;
  final String label;

  static DocumentStatus fromId(String id) => DocumentStatus.values.firstWhere(
        (d) => d.id == id,
        orElse: () => DocumentStatus.pendiente,
      );
}

class DriverDocument {
  const DriverDocument({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.url,
    required this.fechaSubida,
  });

  final String id;
  final DocumentType tipo;
  final DocumentStatus estado;
  final String url;
  final DateTime fechaSubida;

  factory DriverDocument.fromMap(Map<String, dynamic> row) => DriverDocument(
        id: row['id'] as String,
        tipo: DocumentType.fromId(row['tipo_documento'] as String),
        estado: DocumentStatus.fromId(row['estado'] as String),
        url: row['url_archivo'] as String,
        fechaSubida:
            DateTime.tryParse(row['fecha_subida'] as String)?.toLocal() ??
                DateTime.now(),
      );
}

/// Aviso de `public.notificaciones`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    required this.fecha,
  });

  final String id;
  final String titulo;
  final String mensaje;
  final bool leida;
  final DateTime fecha;

  factory AppNotification.fromMap(Map<String, dynamic> row) => AppNotification(
        id: row['id'] as String,
        titulo: row['titulo'] as String,
        mensaje: row['mensaje'] as String,
        leida: row['leida'] as bool,
        fecha: DateTime.tryParse(row['fecha'] as String)?.toLocal() ??
            DateTime.now(),
      );

  /// Texto relativo para la lista: «hace 5 min», «ayer».
  String get cuando {
    final d = DateTime.now().difference(fecha);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays == 1) return 'ayer';
    return 'hace ${d.inDays} días';
  }
}

/// Método de pago del pasajero.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.tipo,
    required this.predeterminado,
    this.detalle,
  });

  final String id;

  /// `tarjeta` o `efectivo`.
  final String tipo;
  final bool predeterminado;

  /// Token de la pasarela. Nunca el número real de la tarjeta.
  final String? detalle;

  bool get esEfectivo => tipo == 'efectivo';

  String get label => esEfectivo ? 'Efectivo' : 'Tarjeta';

  /// Qué se muestra en la lista. Del token solo se enseñan los últimos
  /// caracteres: no es un número de tarjeta, pero tampoco hace falta exhibirlo.
  String get descripcion {
    if (esEfectivo) return 'Pagas al llegar';
    final t = detalle ?? '';
    return t.length <= 4 ? 'Tarjeta guardada' : '···· ${t.substring(t.length - 4)}';
  }

  factory PaymentMethod.fromMap(Map<String, dynamic> row) => PaymentMethod(
        id: row['id'] as String,
        tipo: row['tipo'] as String,
        predeterminado: row['predeterminado'] as bool,
        detalle: row['detalle_tokenizado'] as String?,
      );
}

/// Un chofer visto por la administración, tal como lo devuelve la vista
/// `public.conductores_revision`.
///
/// Reúne en una fila lo que hace falta para decidir si se aprueba: quién es,
/// cómo contactarlo, qué vehículos registró y en qué estado está cada uno de
/// sus documentos. Antes esto no se podía consultar desde la app: los papeles
/// que subía un chofer no los veía nadie.
class DriverReview {
  const DriverReview({
    required this.id,
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.fotoUrl,
    required this.estadoAprobacion,
    required this.disponible,
    required this.calificacion,
    required this.fechaRegistro,
    required this.vehiculos,
    required this.documentos,
  });

  final String id;
  final String nombre;
  final String email;

  /// El número que registró la persona. Puede faltar: el registro lo pide,
  /// pero una cuenta creada antes de esa validación puede no tenerlo.
  final String? telefono;
  final String? fotoUrl;

  /// `pendiente`, `aprobado` o `rechazado`.
  final String estadoAprobacion;
  final bool disponible;
  final double? calificacion;
  final DateTime? fechaRegistro;

  final List<FleetVehicle> vehiculos;
  final List<DriverDocument> documentos;

  bool get aprobado => estadoAprobacion == 'aprobado';
  bool get rechazado => estadoAprobacion == 'rechazado';

  FleetVehicle? get vehiculoActivo {
    for (final v in vehiculos) {
      if (v.activo) return v;
    }
    return vehiculos.isEmpty ? null : vehiculos.first;
  }

  DriverDocument? documento(DocumentType tipo) {
    for (final d in documentos) {
      if (d.tipo == tipo) return d;
    }
    return null;
  }

  int get aprobados =>
      documentos.where((d) => d.estado == DocumentStatus.aprobado).length;

  int get pendientes =>
      documentos.where((d) => d.estado == DocumentStatus.pendiente).length;

  /// Los tipos que todavía no están aprobados. Es exactamente lo que
  /// `revisar_conductor` exige antes de dejar aprobar la cuenta.
  List<DocumentType> get faltantes => [
        for (final tipo in DocumentType.values)
          if (documento(tipo)?.estado != DocumentStatus.aprobado) tipo,
      ];

  /// Se puede aprobar cuando no falta ningún documento y hay al menos un auto.
  /// La comprobación de verdad la hace Postgres; esto solo evita ofrecer un
  /// botón que se sabe que va a rebotar.
  bool get listoParaAprobar => faltantes.isEmpty && vehiculos.isNotEmpty;

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes[1][0]).toUpperCase();
  }

  factory DriverReview.fromMap(Map<String, dynamic> row) {
    final autos = (row['vehiculos'] as List?) ?? const [];
    final docs = (row['documentos'] as List?) ?? const [];
    final nombre = (row['nombre'] as String?)?.trim();
    final email = (row['email'] as String?) ?? '';

    return DriverReview(
      id: row['id'] as String,
      // Sin nombre se usa la parte local del correo: en una lista de revisión,
      // una fila sin título no se puede distinguir de otra.
      nombre: (nombre == null || nombre.isEmpty) ? email.split('@').first : nombre,
      email: email,
      telefono: (row['telefono'] as String?)?.trim(),
      fotoUrl: row['foto_url'] as String?,
      estadoAprobacion: (row['estado_aprobacion'] as String?) ?? 'pendiente',
      disponible: (row['disponible'] as bool?) ?? false,
      calificacion: (row['calificacion_promedio'] as num?)?.toDouble(),
      fechaRegistro: row['fecha_registro'] == null
          ? null
          : DateTime.tryParse(row['fecha_registro'] as String)?.toLocal(),
      vehiculos: [
        for (final v in autos)
          FleetVehicle.fromMap(Map<String, dynamic>.from(v as Map)),
      ],
      documentos: [
        for (final d in docs)
          DriverDocument.fromMap(Map<String, dynamic>.from(d as Map)),
      ],
    );
  }
}
