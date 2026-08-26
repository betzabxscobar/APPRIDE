import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Estados del viaje. Son exactamente los nueve valores del tipo
/// `public.enum_estado_viaje` en Postgres (sección 2.4 del informe).
///
/// El orden importa: [activos] y [esFinal] se apoyan en él.
enum TripStatus {
  solicitado('SOLICITADO', 'Solicitado', 'Registrando tu solicitud'),
  buscandoConductor('BUSCANDO_CONDUCTOR', 'Buscando chofer',
      'Avisando a los choferes cercanos'),
  aceptado('ACEPTADO', 'Chofer asignado', 'Un chofer tomó tu viaje'),
  conductorEnCamino('CONDUCTOR_EN_CAMINO', 'Chofer en camino',
      'Se dirige a tu punto de recogida'),
  conductorEnOrigen('CONDUCTOR_EN_ORIGEN', 'Chofer en el punto',
      'Ya llegó, sal cuando puedas'),
  enCurso('EN_CURSO', 'En viaje', 'Vas rumbo a tu destino'),
  finalizado('FINALIZADO', 'Finalizado', 'Llegaste a tu destino'),
  cancelado('CANCELADO', 'Cancelado', 'El viaje fue cancelado'),
  sinConductor('SIN_CONDUCTOR', 'Sin choferes',
      'Nadie tomó el viaje a tiempo');

  const TripStatus(this.id, this.label, this.hint);

  /// Valor tal como viaja en la base.
  final String id;
  final String label;

  /// Frase para el pasajero, en la pantalla de seguimiento.
  final String hint;

  bool get esFinal =>
      this == finalizado || this == cancelado || this == sinConductor;

  /// El viaje sigue vivo: hay algo que mostrar y que actualizar.
  bool get esActivo => !esFinal;

  /// Ya hay un chofer asignado a quien mostrar.
  bool get tieneConductor => index >= aceptado.index && !esFinal;

  /// Todavía se puede cancelar. `EN_CURSO` ya no: la persona va a bordo.
  bool get sePuedeCancelar => index < enCurso.index;

  /// Cuánto del recorrido lleva, para la barra de progreso (0 a 1).
  double get progreso => switch (this) {
        solicitado => 0.08,
        buscandoConductor => 0.2,
        aceptado => 0.4,
        conductorEnCamino => 0.55,
        conductorEnOrigen => 0.7,
        enCurso => 0.9,
        _ => 1,
      };

  Color get color => switch (this) {
        finalizado => AppColors.green,
        cancelado || sinConductor => AppColors.danger,
        enCurso => AppColors.primary,
        _ => AppColors.purple,
      };

  static TripStatus fromId(String id) => TripStatus.values.firstWhere(
        (estado) => estado.id == id,
        orElse: () => TripStatus.solicitado,
      );
}

/// Punto del catálogo `public.lugares`.
class Place {
  const Place({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String nombre;
  final String direccion;
  final double lat;
  final double lng;

  factory Place.fromMap(Map<String, dynamic> row) => Place(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        direccion: row['direccion'] as String,
        lat: (row['latitud'] as num).toDouble(),
        lng: (row['longitud'] as num).toDouble(),
      );
}

/// Cotización devuelta por `public.cotizar_viaje`.
///
/// El total lo calcula el servidor. La app solo lo muestra: si el precio
/// viniera del cliente, cualquiera podría pedir un viaje por un centavo.
class Quote {
  const Quote({
    required this.tarifaId,
    required this.tarifaNombre,
    required this.km,
    required this.minutos,
    required this.total,
  });

  final String tarifaId;
  final String tarifaNombre;
  final double km;
  final int minutos;
  final double total;

  factory Quote.fromMap(Map<String, dynamic> row) => Quote(
        tarifaId: row['tarifa_id'] as String,
        tarifaNombre: row['tarifa_nombre'] as String,
        km: (row['distancia_km'] as num).toDouble(),
        minutos: (row['minutos_estimados'] as num).toInt(),
        total: (row['total'] as num).toDouble(),
      );
}

/// Viaje con los datos ya combinados, tal como los devuelve la vista
/// `public.viajes_detalle`.
class Trip {
  const Trip({
    required this.id,
    required this.status,
    required this.pasajeroId,
    this.conductorId,
    required this.tarifaEstimada,
    this.tarifaFinal,
    required this.fechaSolicitud,
    this.fechaInicio,
    this.fechaFin,
    required this.tarifaNombre,
    required this.pasajeroNombre,
    this.pasajeroTelefono,
    this.conductorNombre,
    this.conductorTelefono,
    this.conductorCalificacion,
    this.vehiculoPlaca,
    this.vehiculoMarca,
    this.vehiculoModelo,
    this.vehiculoColor,
    required this.origenTexto,
    required this.destinoTexto,
    this.origenLat,
    this.origenLng,
    this.destinoLat,
    this.destinoLng,
  });

  final String id;
  final TripStatus status;
  final String pasajeroId;
  final String? conductorId;
  final double tarifaEstimada;
  final double? tarifaFinal;
  final DateTime fechaSolicitud;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String tarifaNombre;

  final String pasajeroNombre;
  final String? pasajeroTelefono;
  final String? conductorNombre;
  final String? conductorTelefono;
  final double? conductorCalificacion;

  final String? vehiculoPlaca;
  final String? vehiculoMarca;
  final String? vehiculoModelo;
  final String? vehiculoColor;

  final String origenTexto;
  final String destinoTexto;
  final double? origenLat;
  final double? origenLng;
  final double? destinoLat;
  final double? destinoLng;

  /// Lo que se cobra: el definitivo si ya cerró, si no la cotización.
  double get montoVigente => tarifaFinal ?? tarifaEstimada;

  String get vehiculoResumen {
    final partes = [vehiculoMarca, vehiculoModelo].whereType<String>();
    if (partes.isEmpty) return 'Vehículo asignado';
    final base = partes.join(' ');
    return vehiculoColor == null ? base : '$base · $vehiculoColor';
  }

  static double? _double(dynamic v) => v == null ? null : (v as num).toDouble();
  static DateTime? _fecha(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory Trip.fromMap(Map<String, dynamic> row) => Trip(
        id: row['id'] as String,
        status: TripStatus.fromId(row['estado'] as String),
        pasajeroId: row['pasajero_id'] as String,
        conductorId: row['conductor_id'] as String?,
        tarifaEstimada: _double(row['tarifa_estimada']) ?? 0,
        tarifaFinal: _double(row['tarifa_final']),
        fechaSolicitud: _fecha(row['fecha_solicitud']) ?? DateTime.now(),
        fechaInicio: _fecha(row['fecha_inicio']),
        fechaFin: _fecha(row['fecha_fin']),
        tarifaNombre: (row['tarifa_nombre'] as String?) ?? 'Tarifa',
        pasajeroNombre: (row['pasajero_nombre'] as String?) ?? 'Pasajero',
        pasajeroTelefono: row['pasajero_telefono'] as String?,
        conductorNombre: row['conductor_nombre'] as String?,
        conductorTelefono: row['conductor_telefono'] as String?,
        conductorCalificacion: _double(row['conductor_calificacion']),
        vehiculoPlaca: row['vehiculo_placa'] as String?,
        vehiculoMarca: row['vehiculo_marca'] as String?,
        vehiculoModelo: row['vehiculo_modelo'] as String?,
        vehiculoColor: row['vehiculo_color'] as String?,
        origenTexto: (row['origen_texto'] as String?) ?? 'Origen',
        destinoTexto: (row['destino_texto'] as String?) ?? 'Destino',
        origenLat: _double(row['origen_lat']),
        origenLng: _double(row['origen_lng']),
        destinoLat: _double(row['destino_lat']),
        destinoLng: _double(row['destino_lng']),
      );
}
