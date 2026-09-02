import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Piezas compartidas por las pantallas con mapa de fondo.
///
/// Sobre un mapa no sirve el estilo del resto de la app: un icono o un texto
/// sueltos desaparecen en cuanto pasan por encima de una avenida clara o de un
/// parque verde. Todo lo que flote sobre el mapa necesita superficie propia y
/// sombra.

/// Cápsula opaca para un control que flota sobre el mapa.
class MapCapsule extends StatelessWidget {
  const MapCapsule({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: ride.isDark ? const Color(0x99000000) : ride.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: ride.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// Botón redondo sobre el mapa: centrar en mi ubicación, capas, etc.
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return MapCapsule(
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 23, color: ride.accent),
          ),
        ),
      ),
    );
  }
}

/// Aviso sobre el mapa cuando no sabemos dónde está la persona.
///
/// Existe porque callarse es peor: sin él, el mapa se queda en el centro por
/// defecto —Guayaquil— y quien lo mira cree que la app lo ubicó allí. Un mapa
/// que no sabe dónde estás tiene que decirlo.
class MapNotice extends StatelessWidget {
  const MapNotice({
    super.key,
    required this.mensaje,
    this.cargando = false,
    this.onReintentar,
  });

  final String mensaje;
  final bool cargando;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, onReintentar == null ? 14 : 6, 10),
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusAction),
        border: Border.all(color: ride.border),
        boxShadow: [
          BoxShadow(
            color: ride.isDark ? const Color(0x99000000) : ride.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cargando)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: ride.accent,
              ),
            )
          else
            Icon(Icons.location_off_outlined, size: 20, color: ride.inkMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              mensaje,
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ride.ink,
              ),
            ),
          ),
          if (onReintentar != null)
            TextButton(
              onPressed: onReintentar,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}

/// Superficie de una hoja arrastrable montada sobre el mapa.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusSheet),
        ),
        // El borde superior es lo que separa la hoja del mapa en modo oscuro,
        // donde la sombra no se distingue.
        border: Border(top: BorderSide(color: ride.border)),
        boxShadow: [
          BoxShadow(
            color: ride.isDark ? const Color(0xAA000000) : ride.shadow,
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Agarradera de la hoja: indica que se puede arrastrar.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(top: 12, bottom: 18),
        decoration: BoxDecoration(
          color: context.ride.borderStrong,
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}
