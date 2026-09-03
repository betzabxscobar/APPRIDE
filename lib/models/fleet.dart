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

/// Los papeles que la administración exige para aprobar a un chofer.
///
/// Se dividen en dos, y la división importa: los de la persona son uno por
/// cuenta, y los del vehículo son **uno por cada auto**. Un chofer con dos
/// autos necesita dos matrículas, dos SPPAT y dos revisiones técnicas.
///
/// `SPPAT` reemplazó al SOAT en Ecuador: es el Servicio Público para Pago de
/// Accidentes de Tránsito.
enum DocumentType {
  cedula('cedula', 'Cédula de identidad', 'Foto del frente de tu cédula',
      Icons.badge_outlined),
  licencia('licencia', 'Licencia de conducir',
      'Foto del frente de tu licencia vigente', Icons.credit_card_outlined),
  fotoPerfil('foto_perfil', 'Tu foto',
      'De frente y con la cara descubierta: es la que ve el pasajero',
      Icons.person_outline),
  matricula('matricula', 'Matrícula', 'La del vehículo, vigente',
      Icons.description_outlined, deVehiculo: true, caduca: true),
  sppat('SPPAT', 'SPPAT', 'El seguro que reemplazó al SOAT',
      Icons.shield_outlined, deVehiculo: true, caduca: true),
  revisionTecnica('revision_tecnica', 'Revisión técnica',
      'La del año en curso', Icons.build_outlined,
      deVehiculo: true, caduca: true),
  fotoVehiculo('foto_vehiculo', 'Foto del vehículo',
      'De frente y con la placa legible', Icons.directions_car_outlined,
      deVehiculo: true);

  const DocumentType(
    this.id,
    this.label,
    this.hint,
    this.icon, {
    this.deVehiculo = false,
    this.caduca = false,
  });

  /// Valor tal como lo espera la base.
  final String id;
  final String label;
  final String hint;
  final IconData icon;

  /// Si es de un auto concreto. Los demás son de la persona.
  final bool deVehiculo;

  /// Si lleva fecha de caducidad obligatoria. Una foto no caduca.
  final bool caduca;

  static List<DocumentType> get delChofer =>
      DocumentType.values.where((d) => !d.deVehiculo).toList();

  static List<DocumentType> get delVehiculo =>
      DocumentType.values.where((d) => d.deVehiculo).toList();

  static DocumentType fromId(String id) => DocumentType.values.firstWhere(
        (d) => d.id == id,
        orElse: () => DocumentType.licencia,
      );
}

/// Tipos de licencia de la ANT.
///
/// Cuál habilita para qué categoría **no se decide aquí**: está en la tabla
/// `licencias_por_categoria`, porque eso lo cambia una resolución de la ANT y
/// no puede exigir volver a compilar la app.
enum LicenseType {
  a('A', 'A · Motocicletas'),
  a1('A1', 'A1 · Tricimotos y cuadrones'),
  b('B', 'B · Particular, hasta 3.500 kg'),
  c('C', 'C · Profesional, taxis y transporte liviano'),
  c1('C1', 'C1 · Profesional, vehículos de instituciones'),
  d('D', 'D · Profesional, transporte público de pasajeros'),
  d1('D1', 'D1 · Profesional, turismo'),
  e('E', 'E · Profesional, carga pesada'),
  e1('E1', 'E1 · Profesional, carga pesada articulada'),
  f('F', 'F · Adaptados para personas con discapacidad'),
  g('G', 'G · Maquinaria agrícola y equipo pesado');

  const LicenseType(this.id, this.label);
  final String id;
  final String label;

  static LicenseType? fromId(String? id) {
    if (id == null) return null;
    for (final l in LicenseType.values) {
      if (l.id == id) return l;
    }
    return null;
  }
}

/// Quién es el chofer, según `public.conductores`.
///
/// Son los datos que la app no puede inventarse ni deducir de una foto: el
/// número de cédula, el código dactilar del reverso y qué licencia tiene. Sin
/// esto, de la identidad de un chofer solo había imágenes.
class DriverIdentity {
  const DriverIdentity({
    this.cedula,
    this.codigoDactilar,
    this.licencia,
    this.licenciaCaducaEl,
  });

  final String? cedula;
  final String? codigoDactilar;
  final LicenseType? licencia;
  final DateTime? licenciaCaducaEl;

  bool get completa =>
      cedula != null && codigoDactilar != null && licencia != null;

  bool get licenciaVencida {
    final f = licenciaCaducaEl;
    return f == null || f.isBefore(DateTime.now());
  }

  /// La cédula en pantalla se parte para leerla, no para ocultarla: es un dato
  /// que la persona acaba de escribir y que ve en su propio perfil.
  String get cedulaLegible {
    final c = cedula;
    if (c == null || c.length != 10) return c ?? '—';
    return '${c.substring(0, 2)}-${c.substring(2, 9)}-${c.substring(9)}';
  }

  factory DriverIdentity.fromMap(Map<String, dynamic> row) => DriverIdentity(
        cedula: row['cedula'] as String?,
        codigoDactilar: row['codigo_dactilar'] as String?,
        licencia: LicenseType.fromId(row['licencia_tipo'] as String?),
        licenciaCaducaEl:
            DateTime.tryParse((row['licencia_caduca_el'] as String?) ?? ''),
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
    this.vehiculoId,
    this.numero,
    this.caducaEl,
    this.motivoRechazo,
  });

  final String id;
  final DocumentType tipo;
  final DocumentStatus estado;
  final String url;
  final DateTime fechaSubida;

  /// De qué auto es. Null en los de la persona.
  final String? vehiculoId;

  /// Número de la póliza o de la matrícula, para poder cotejarlo.
  final String? numero;
  final DateTime? caducaEl;

  /// Por qué se rechazó. Es lo único que el chofer va a leer, así que sin esto
  /// vuelve a subir exactamente lo mismo.
  final String? motivoRechazo;

  /// Aprobado **y** sin caducar. Un SPPAT vencido no sirve por mucho que
  /// alguien lo haya aprobado en su día.
  bool get vigente {
    if (estado != DocumentStatus.aprobado) return false;
    if (!tipo.caduca) return true;
    final f = caducaEl;
    return f != null && !f.isBefore(DateTime.now());
  }

  /// Caduca dentro de un mes: se avisa antes de que deje de servir.
  bool get porCaducar {
    final f = caducaEl;
    if (!tipo.caduca || f == null) return false;
    final quedan = f.difference(DateTime.now()).inDays;
    return quedan >= 0 && quedan <= 30;
  }

  factory DriverDocument.fromMap(Map<String, dynamic> row) => DriverDocument(
        id: row['id'] as String,
        tipo: DocumentType.fromId(row['tipo_documento'] as String),
        estado: DocumentStatus.fromId(row['estado'] as String),
        url: row['url_archivo'] as String,
        fechaSubida:
            DateTime.tryParse(row['fecha_subida'] as String)?.toLocal() ??
                DateTime.now(),
        vehiculoId: row['vehiculo_id'] as String?,
        numero: row['numero'] as String?,
        caducaEl: DateTime.tryParse((row['caduca_el'] as String?) ?? ''),
        motivoRechazo: row['motivo_rechazo'] as String?,
      );
}

/// Lo que le falta a un chofer, tal como lo devuelve
/// `papeles_que_faltan_chofer()`.
///
/// Los identificadores llegan del servidor y se traducen aquí. Que la lista la
/// arme Postgres y no la app es lo que evita que la pantalla diga «ya está»
/// mientras la función que aprueba piensa lo contrario.
String etiquetaDePapel(String id) => switch (id) {
      'identidad' => 'Cédula, código dactilar y tipo de licencia',
      'licencia_vigente' => 'Una licencia sin caducar',
      'vehiculo_completo' => 'Un vehículo con todos sus papeles al día',
      _ => DocumentType.fromId(id).label,
    };

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

  /// `tarjeta`, `efectivo` o `deuna`.
  final String tipo;
  final bool predeterminado;

  /// Token de la pasarela. Nunca el número real de la tarjeta.
  final String? detalle;

  bool get esEfectivo => tipo == 'efectivo';

  /// DeUna no guarda nada en el teléfono: cada viaje se paga escaneando su
  /// propio QR. Por eso es un método sin token, como el efectivo.
  bool get esDeuna => tipo == 'deuna';

  String get label => switch (tipo) {
        'efectivo' => 'Efectivo',
        'deuna' => 'DeUna',
        _ => 'Tarjeta',
      };

  IconData get icon => switch (tipo) {
        'efectivo' => Icons.payments_outlined,
        'deuna' => Icons.qr_code_2,
        _ => Icons.credit_card,
      };

  /// Qué se muestra en la lista. Del token solo se enseñan los últimos
  /// caracteres: no es un número de tarjeta, pero tampoco hace falta exhibirlo.
  String get descripcion {
    if (esEfectivo) return 'Pagas al llegar';
    if (esDeuna) return 'Escaneas el QR al terminar';
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
    required this.papelesQueFaltan,
    this.cedula,
    this.codigoDactilar,
    this.licencia,
    this.licenciaCaducaEl,
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

  /// Lo que le falta, calculado por `papeles_que_faltan_chofer()`. Llega del
  /// servidor y no se recalcula aquí a propósito: si la pantalla tuviera su
  /// propia idea de «completo», acabaría discrepando de la función que aprueba.
  final List<String> papelesQueFaltan;

  final String? cedula;
  final String? codigoDactilar;
  final LicenseType? licencia;
  final DateTime? licenciaCaducaEl;

  bool get licenciaVencida =>
      licenciaCaducaEl == null || licenciaCaducaEl!.isBefore(DateTime.now());

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

  /// Los papeles de ese vehículo, para revisarlos junto al auto al que
  /// pertenecen y no en una lista suelta donde no se sabe de cuál son.
  List<DriverDocument> documentosDe(String vehiculoId) =>
      documentos.where((d) => d.vehiculoId == vehiculoId).toList();

  /// Lo que falta, ya en castellano.
  List<String> get faltantes =>
      papelesQueFaltan.map(etiquetaDePapel).toList();

  /// Se puede aprobar cuando el servidor dice que no falta nada. La
  /// comprobación de verdad la hace `revisar_conductor`; esto solo evita
  /// ofrecer un botón que se sabe que va a rebotar.
  bool get listoParaAprobar => papelesQueFaltan.isEmpty;

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
      papelesQueFaltan: [
        for (final f in (row['papeles_que_faltan'] as List?) ?? const [])
          f as String,
      ],
      cedula: row['cedula'] as String?,
      codigoDactilar: row['codigo_dactilar'] as String?,
      licencia: LicenseType.fromId(row['licencia_tipo'] as String?),
      licenciaCaducaEl:
          DateTime.tryParse((row['licencia_caduca_el'] as String?) ?? ''),
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
