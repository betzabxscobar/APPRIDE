import 'package:flutter/material.dart';

/// Un tipo de vehículo: moto, estándar, confort, XL.
///
/// Sale de `public.categorias_vehiculo`, **no está escrito en la app**. Los
/// precios y los tipos se ajustan con un UPDATE en la base, igual que las
/// tarifas, sin publicar una versión nueva.
///
/// El [factor] no se usa para calcular nada aquí: el precio lo da el servidor
/// en `cotizar_categorias`. Está para poder enseñarlo («×1,3») cuando ayude a
/// entender por qué una opción cuesta más.
class VehicleCategory {
  const VehicleCategory({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.pasajeros,
    required this.icono,
    required this.orden,
    this.factor,
  });

  /// `moto`, `estandar`, `confort`, `xl`.
  final String id;
  final String nombre;
  final String descripcion;
  final int pasajeros;

  /// Nombre lógico del icono, tal como lo guarda la base. Se traduce con
  /// [icon]: en la base no se guardan iconos de Flutter.
  final String icono;

  final int orden;

  /// Multiplicador sobre la tarifa vigente. Puede no venir: la cotización no
  /// lo devuelve porque no lo necesita.
  final double? factor;

  /// El icono de Material que le toca.
  ///
  /// El `switch` está aquí y no en la base a propósito: un `IconData` es un
  /// número de la fuente de iconos de Flutter, y guardarlo en Postgres ataría
  /// la base a una versión concreta del framework. La base dice «moto»; qué
  /// dibujo es una moto lo decide la app.
  IconData get icon => iconoDe(icono);

  /// El icono que corresponde a un nombre lógico de la base.
  ///
  /// Estático porque un viaje guarda el nombre del icono suelto
  /// (`Trip.categoriaIcono`), sin la categoría entera detrás.
  static IconData iconoDe(String? nombre) => switch (nombre) {
        'moto' => Icons.two_wheeler,
        'auto' => Icons.directions_car,
        'confort' => Icons.local_taxi,
        'van' => Icons.airport_shuttle,
        _ => Icons.directions_car,
      };

  /// «1 pasajero» / «hasta 4 pasajeros».
  String get capacidad =>
      pasajeros == 1 ? '1 pasajero' : 'hasta $pasajeros pasajeros';

  factory VehicleCategory.fromMap(Map<String, dynamic> row) => VehicleCategory(
        id: (row['id'] ?? row['categoria']) as String,
        nombre: row['nombre'] as String,
        descripcion: (row['descripcion'] as String?) ?? '',
        pasajeros: (row['pasajeros'] as num?)?.toInt() ?? 4,
        icono: (row['icono'] as String?) ?? 'auto',
        orden: (row['orden'] as num?)?.toInt() ?? 0,
        factor: (row['factor'] as num?)?.toDouble(),
      );

  /// La que se asume mientras no llega el catálogo.
  ///
  /// Es la misma que aplica la base por defecto, así que una app que arranque
  /// sin red no pide algo distinto de lo que el servidor entendería.
  static const String idPorDefecto = 'estandar';
}

/// Una categoría con su precio ya calculado para un trayecto concreto.
///
/// Los precios llegan del servidor, uno por categoría, en una sola llamada. No
/// se calculan en el cliente multiplicando por el factor: el redondeo y la
/// carrera mínima no son lineales y el número mostrado no cuadraría con el
/// cobrado.
class CategoryQuote {
  const CategoryQuote({
    required this.categoria,
    required this.total,
    required this.distanciaKm,
    required this.minutos,
    required this.ganaConductor,
    required this.aplicoMinima,
  });

  final VehicleCategory categoria;
  final double total;
  final double distanciaKm;
  final int minutos;
  final double ganaConductor;

  /// `true` si el viaje es tan corto que se cobró la carrera mínima.
  final bool aplicoMinima;

  factory CategoryQuote.fromMap(Map<String, dynamic> row) => CategoryQuote(
        categoria: VehicleCategory.fromMap(row),
        total: (row['total'] as num).toDouble(),
        distanciaKm: (row['distancia_km'] as num?)?.toDouble() ?? 0,
        minutos: (row['minutos_estimados'] as num?)?.toInt() ?? 0,
        ganaConductor: (row['gana_conductor'] as num?)?.toDouble() ?? 0,
        aplicoMinima: (row['aplico_minima'] as bool?) ?? false,
      );
}
