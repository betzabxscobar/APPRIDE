import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Roles de Ride. Son los mismos cuatro que maneja el backend de WEB-RIDE:
/// `passenger`, `driver`, `admin` y `superadmin`.
///
/// Solo [selectable] se ofrece en la app: las cuentas administrativas no se
/// registran desde aquí, las crea el equipo y llegan con contraseña temporal.
enum UserRole {
  passenger(
    id: 'passenger',
    label: 'Viajo',
    description: 'Quiero solicitar viajes',
    icon: Icons.person_outline,
    accent: AppColors.primary,
    accentSoft: AppColors.primarySoft,
  ),
  driver(
    id: 'driver',
    label: 'Conduzco',
    description: 'Quiero ofrecer viajes',
    icon: Icons.drive_eta_outlined,
    accent: AppColors.green,
    accentSoft: AppColors.greenSoft,
  ),
  admin(
    id: 'admin',
    label: 'Administro',
    description: 'Panel de gestión',
    icon: Icons.shield_outlined,
    accent: AppColors.purple,
    accentSoft: AppColors.purpleSoft,
  ),
  superadmin(
    id: 'superadmin',
    label: 'Superadmin',
    description: 'Control total',
    icon: Icons.workspace_premium_outlined,
    accent: AppColors.purple,
    accentSoft: AppColors.purpleSoft,
  );

  const UserRole({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
    required this.accentSoft,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color accent;
  final Color accentSoft;

  /// Roles que una persona puede elegir al entrar o registrarse.
  static const List<UserRole> selectable = [passenger, driver];

  bool get isDriver => this == UserRole.driver;
  bool get isPassenger => this == UserRole.passenger;

  /// `admin` y `superadmin` comparten el panel; solo cambian los permisos.
  bool get isAdministrative =>
      this == UserRole.admin || this == UserRole.superadmin;
  bool get isSuperadmin => this == UserRole.superadmin;

  /// Nombre del rol tal como se muestra dentro de la app.
  String get displayName => switch (this) {
        UserRole.passenger => 'Pasajero',
        UserRole.driver => 'Conductor',
        UserRole.admin => 'Administrador',
        UserRole.superadmin => 'Superadministrador',
      };

  /// Vistas a las que puede entrar una cuenta con este rol.
  ///
  /// Es la regla central del cambio de panel, aparte a propósito para poder
  /// probarla sin sesión:
  ///
  /// - `superadmin`: su panel, el panel visto como admin, usuario y chofer.
  /// - `admin`: su panel, usuario y chofer. **Nunca** la vista de superadmin.
  /// - `driver`: chofer y usuario.
  /// - `passenger`: usuario, y chofer solo si ya registró un vehículo.
  ///
  /// Esto decide qué se ofrece en pantalla. Los permisos sobre los datos los
  /// sigue resolviendo RLS con el rol real de la cuenta.
  List<UserRole> viewsAllowed({bool hasVehicle = false}) {
    return switch (this) {
      UserRole.superadmin => const [superadmin, admin, passenger, driver],
      UserRole.admin => const [admin, passenger, driver],
      UserRole.driver => const [driver, passenger],
      UserRole.passenger =>
        hasVehicle ? const [passenger, driver] : const [passenger],
    };
  }

  static UserRole fromId(String id) {
    return UserRole.values.firstWhere(
      (role) => role.id == id,
      orElse: () => UserRole.passenger,
    );
  }
}
