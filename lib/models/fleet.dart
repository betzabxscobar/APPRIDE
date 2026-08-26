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
  });

  final String id;
  final String placa;
  final String marca;
  final String modelo;
  final int anio;
  final bool activo;
  final String? color;

  String get resumen => '$marca $modelo · $anio';

  factory FleetVehicle.fromMap(Map<String, dynamic> row) => FleetVehicle(
        id: row['id'] as String,
        placa: row['placa'] as String,
        marca: row['marca'] as String,
        modelo: row['modelo'] as String,
        anio: (row['anio'] as num).toInt(),
        activo: row['activo'] as bool,
        color: row['color'] as String?,
      );
}

/// Los tres documentos que la administración exige para aprobar a un chofer.
enum DocumentType {
  licencia('licencia', 'Licencia de conducir',
      'Foto del frente de tu licencia vigente'),
  soat('SOAT', 'SOAT', 'Póliza del seguro obligatorio'),
  matricula('matricula', 'Matrícula', 'Matrícula del vehículo');

  const DocumentType(this.id, this.label, this.hint);

  /// Valor tal como lo espera la base.
  final String id;
  final String label;
  final String hint;

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
