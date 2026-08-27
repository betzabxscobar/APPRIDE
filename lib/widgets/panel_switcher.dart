import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';

/// Nombre de la vista tal como se ofrece en el selector.
///
/// No es el `displayName` del rol: aquí se nombra la *pantalla*, no la cuenta.
/// Un superadmin que abre la vista de pasajero no pasa a ser pasajero.
String panelLabel(UserRole view) => switch (view) {
      UserRole.superadmin => 'Panel de superadmin',
      UserRole.admin => 'Panel de administración',
      UserRole.passenger => 'Vista de usuario',
      UserRole.driver => 'Vista de chofer',
    };

/// Selector de panel para moverse entre las vistas que permite la cuenta.
///
/// Solo aparece cuando hay más de una vista disponible. Las opciones salen de
/// [AuthService.availableViews], que es quien decide qué puede ver cada rol:
/// un `admin` nunca recibe la vista de superadmin.
class PanelSwitcher extends StatelessWidget {
  const PanelSwitcher({super.key, this.onSwitched});

  /// Se llama tras cambiar de vista, por si la pantalla debe cerrar una hoja
  /// o un menú antes de que la raíz reconstruya.
  final VoidCallback? onSwitched;

  @override
  Widget build(BuildContext context) {
    final service = AuthService.instance;
    final views = service.availableViews;
    if (views.length < 2) return const SizedBox.shrink();

    final active = service.activeView;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'CAMBIAR DE PANEL',
            style: TextStyle(
              fontSize: AppText.micro,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: context.ride.inkMuted,
            ),
          ),
        ),
        for (final view in views)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PanelOption(
              view: view,
              selected: view == active,
              onTap: view == active
                  ? null
                  : () => _switch(context, service, view),
            ),
          ),
      ],
    );
  }

  void _switch(BuildContext context, AuthService service, UserRole view) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      service.switchView(view);
      onSwitched?.call();
    } on AuthException catch (e) {
      onSwitched?.call();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _PanelOption extends StatelessWidget {
  const _PanelOption({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final UserRole view;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final radius = BorderRadius.circular(AppTheme.radiusAction);
    // Los `accentSoft` del rol son tintes muy claros pensados para fondo
    // blanco. Sobre el tema oscuro deslumbran, así que allí el resaltado se
    // hace con el propio acento a baja opacidad.
    final fondoSeleccion =
        ride.isDark ? view.accent.withValues(alpha: 0.18) : view.accentSoft;

    return Material(
      color: selected ? fondoSeleccion : ride.surfaceAlt,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? view.accent : ride.border,
              width: selected ? 1.8 : 1.4,
            ),
          ),
          child: Row(
            children: [
              Icon(view.icon, size: 22, color: view.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  panelLabel(view),
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w700,
                    color: selected ? view.accent : ride.ink,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: view.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso de que se está mirando una pantalla distinta a la del rol propio.
///
/// Va como `appBar` del Scaffold. Cuando no aplica ocupa cero alto, así que un
/// pasajero de verdad no ve nada.
///
/// Evita la confusión de «¿por qué no veo mis herramientas de administración?»
/// y da una salida directa de vuelta al panel propio.
class ViewingAsBar extends StatelessWidget implements PreferredSizeWidget {
  const ViewingAsBar({super.key});

  static const double _alto = 52;

  @override
  Size get preferredSize => AuthService.instance.isViewingOtherPanel
      ? const Size.fromHeight(_alto)
      : Size.zero;

  @override
  Widget build(BuildContext context) {
    final service = AuthService.instance;
    final realRole = service.currentUser?.role;
    if (!service.isViewingOtherPanel || realRole == null) {
      return const SizedBox.shrink();
    }

    final ride = context.ride;

    return Material(
      color: ride.infoSoft,
      child: SizedBox(
        height: _alto,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 6),
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 18, color: ride.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Viendo como ${realRole.displayName.toLowerCase()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.label,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: ride.ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => AuthService.instance.resetView(),
                style: TextButton.styleFrom(
                  foregroundColor: ride.info,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Volver a mi panel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
