/// Datos del vehículo que registra un conductor.
class Vehicle {
  const Vehicle({
    required this.model,
    required this.plate,
    required this.year,
    this.color,
  });

  final String model;
  final String plate;
  final int year;
  final String? color;

  String get summary => '$model · $year';

  Map<String, dynamic> toMap() => {
        'model': model,
        'plate': plate,
        'year': year,
        'color': color,
      };

  factory Vehicle.fromMap(Map<String, dynamic> map) => Vehicle(
        model: map['model'] as String,
        plate: map['plate'] as String,
        year: map['year'] as int,
        color: map['color'] as String?,
      );
}
