/// Una tarifa de `public.tarifas`: lo que cuesta un viaje en una franja
/// horaria.
///
/// El servidor elige cuál aplica según la hora con `tarifa_vigente()`. La app
/// no decide precios; esto es para poder verlos y ajustarlos.
class Fare {
  const Fare({
    required this.id,
    required this.nombre,
    required this.base,
    required this.porKm,
    required this.porMinuto,
    required this.minima,
    required this.porcentajeConductor,
    required this.activo,
    this.horaDesde,
    this.horaHasta,
  });

  final String id;
  final String nombre;

  /// Lo que se cobra por subirse.
  final double base;
  final double porKm;
  final double porMinuto;

  /// Suelo: por debajo de esto no baja ningún viaje.
  final double minima;

  /// Qué parte se lleva el chofer. 0,85 = 85 %.
  final double porcentajeConductor;

  final bool activo;

  /// Franja horaria. En null, es la de por defecto.
  final int? horaDesde;
  final int? horaHasta;

  /// «22:00 – 05:00» o «El resto del día».
  String get franja {
    if (horaDesde == null || horaHasta == null) return 'El resto del día';
    final d = horaDesde.toString().padLeft(2, '0');
    final h = horaHasta.toString().padLeft(2, '0');
    return '$d:00 – $h:00';
  }

  /// Lo que costaría un viaje de [km] en esta tarifa, sin multiplicador de
  /// categoría. Es la misma cuenta que hace `cotizar_viaje`: arranque más
  /// distancia, con la mínima como suelo.
  double ejemplo(double km) {
    final bruto = base + porKm * km;
    return bruto < minima ? minima : bruto;
  }

  factory Fare.fromMap(Map<String, dynamic> row) => Fare(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        base: (row['tarifa_base'] as num).toDouble(),
        porKm: (row['costo_por_km'] as num).toDouble(),
        porMinuto: (row['costo_por_minuto'] as num?)?.toDouble() ?? 0,
        minima: (row['carrera_minima'] as num).toDouble(),
        porcentajeConductor:
            (row['porcentaje_conductor'] as num?)?.toDouble() ?? 0.85,
        activo: (row['activo'] as bool?) ?? true,
        horaDesde: (row['hora_desde'] as num?)?.toInt(),
        horaHasta: (row['hora_hasta'] as num?)?.toInt(),
      );
}
