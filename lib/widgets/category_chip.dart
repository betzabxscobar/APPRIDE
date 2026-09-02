import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../models/vehicle_category.dart';

/// El tipo de vehículo de un viaje, en pequeño.
///
/// Se repite en tres sitios —la solicitud que ve el chofer, el seguimiento del
/// pasajero y la ficha del vehículo— y en los tres tiene que leerse igual, así
/// que vive aquí en vez de copiarse.
///
/// Se esconde solo cuando el viaje no trae categoría: los viajes anteriores a
/// que existieran los tipos no la tienen, y un distintivo vacío confunde más
/// que la ausencia.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.nombre,
    required this.icono,
    this.destacado = false,
  });

  final String? nombre;
  final String? icono;

  /// En color de acento, para cuando es el dato principal de la tarjeta.
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final texto = nombre;
    if (texto == null || texto.isEmpty) return const SizedBox.shrink();

    final ride = context.ride;
    final color = destacado ? ride.accent : ride.inkMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: destacado ? ride.accentSoft : ride.surfaceAlt,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(VehicleCategory.iconoDe(icono), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: AppText.micro,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
