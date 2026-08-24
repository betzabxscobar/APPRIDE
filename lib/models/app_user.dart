import 'user_role.dart';
import 'vehicle.dart';

/// Usuario autenticado de Ride.
///
/// Los campos replican el perfil público que devuelve la API de WEB-RIDE
/// (`/api/login`, `/api/register`, `/api/me`) sin el hash de la contraseña.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.vehicle,
    this.isVerified = false,
    this.mustChangePassword = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;

  /// Solo presente cuando el rol es [UserRole.driver].
  final Vehicle? vehicle;
  final bool isVerified;

  /// Las cuentas administrativas nacen con contraseña temporal y deben
  /// reemplazarla antes de entrar al panel.
  final bool mustChangePassword;
  final DateTime? createdAt;

  /// Primer nombre, para saludos del tipo "¡Hola, Andrea!".
  String get firstName => name.trim().split(' ').first;

  /// Iniciales para el avatar cuando no hay foto.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  AppUser copyWith({
    UserRole? role,
    Vehicle? vehicle,
    bool? isVerified,
    bool? mustChangePassword,
  }) {
    return AppUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      role: role ?? this.role,
      vehicle: vehicle ?? this.vehicle,
      isVerified: isVerified ?? this.isVerified,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'role': role.id,
        'vehicle': vehicle?.toMap(),
        'isVerified': isVerified,
        'mustChangePassword': mustChangePassword,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        phone: map['phone'] as String,
        role: UserRole.fromId(map['role'] as String),
        vehicle: map['vehicle'] == null
            ? null
            : Vehicle.fromMap(Map<String, dynamic>.from(map['vehicle'] as Map)),
        isVerified: map['isVerified'] as bool? ?? false,
        mustChangePassword: map['mustChangePassword'] as bool? ?? false,
        createdAt: map['createdAt'] == null
            ? null
            : DateTime.tryParse(map['createdAt'] as String),
      );
}
