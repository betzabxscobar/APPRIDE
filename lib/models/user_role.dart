import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Los dos roles que puede tener una cuenta en Ride.
enum UserRole {
  passenger(
    id: 'passenger',
    label: 'Viajo',
    description: 'Necesito un viaje',
    icon: Icons.person_outline,
    accent: AppColors.primary,
    accentSoft: AppColors.primarySoft,
  ),
  driver(
    id: 'driver',
    label: 'Conduzco',
    description: 'Ofrezco viajes',
    icon: Icons.drive_eta_outlined,
    accent: AppColors.green,
    accentSoft: AppColors.greenSoft,
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

  bool get isDriver => this == UserRole.driver;
  bool get isPassenger => this == UserRole.passenger;

  /// Nombre del rol tal como se muestra dentro de la app.
  String get displayName => isDriver ? 'Conductor' : 'Pasajero';

  static UserRole fromId(String id) {
    return UserRole.values.firstWhere(
      (role) => role.id == id,
      orElse: () => UserRole.passenger,
    );
  }
}
