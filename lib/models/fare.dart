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
    this.dias,
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

  /// Días ISO en que aplica la franja: 1 es lunes y 7 domingo. En null, todos.
  ///
  /// Las dos franjas pico van de lunes a viernes, porque el Pico y Placa de
  /// Quito —de donde salen sus horas— no rige el fin de semana.
  final List<int>? dias;

  static const List<String> _nombresDia = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  /// «06:00 – 08:59, de lunes a viernes» o «El resto del día».
  ///
  /// La hora final se escribe en **:59** porque es lo que de verdad hace el
  /// servidor: `tarifa_vigente()` compara la hora entera con un `between`, así
  /// que `hora_hasta = 8` cubre hasta las 08:59. Escribir «08:00» hacía creer
  /// que la franja terminaba una hora antes de lo que termina.
  String get franja {
    if (horaDesde == null || horaHasta == null) return 'El resto del día';
    final d = horaDesde.toString().padLeft(2, '0');
    final h = horaHasta.toString().padLeft(2, '0');
    final horario = '$d:00 – $h:59';
    final cuando = _diasEnPalabras;
    return cuando == null ? horario : '$horario, $cuando';
  }

  /// «de lunes a viernes», «lunes, miércoles» o null si aplica todos los días.
  String? get _diasEnPalabras {
    final d = dias;
    if (d == null) return null;
    if (d.isEmpty) return 'ningún día';

    final orden = [...d]..sort();
    // Un tramo corrido se lee mejor como rango que como lista.
    final corrido =
        orden.length > 2 && orden.last - orden.first == orden.length - 1;
    if (corrido) {
      return 'de ${_nombresDia[orden.first - 1]} a ${_nombresDia[orden.last - 1]}';
    }
    return orden.map((n) => _nombresDia[n - 1]).join(', ');
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
        // Un día fuera de 1..7 sería un dato corrupto; se descarta antes de
        // llegar a `_nombresDia`, que si no reventaría por índice.
        dias: (row['dias'] as List<dynamic>?)
            ?.map((d) => (d as num).toInt())
            .where((d) => d >= 1 && d <= 7)
            .toList(),
      );
}
