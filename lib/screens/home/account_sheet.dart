import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/panel_switcher.dart';

/// Hoja inferior con el perfil, el cambio de rol y el cierre de sesión.
///
/// El color y la forma los pone `bottomSheetTheme`, así que la hoja sigue el
/// tema del teléfono sin repetirlos aquí.
///
/// `isScrollControlled` no es un adorno: sin él la hoja se queda en el alto por
/// defecto (9/16 de la pantalla) y una cuenta de superadmin —que ve tres
/// paneles en el selector— desbordaba por abajo, cortando el botón de cerrar
/// sesión.
Future<void> showAccountSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _AccountSheet(user: user),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return SafeArea(
      child: ConstrainedBox(
        // Deja siempre a la vista el borde superior de la hoja, para que se
        // entienda que es una hoja y se pueda cerrar tocando fuera.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: ride.isDark
                        ? user.role.accent.withValues(alpha: 0.2)
                        : user.role.accentSoft,
                    child: Text(
                      user.initials,
                      style: TextStyle(
                        fontSize: AppText.h3,
                        fontWeight: FontWeight.w800,
                        color: user.role.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            fontSize: AppText.h2,
                            fontWeight: FontWeight.w800,
                            color: ride.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: AppText.small,
                            color: ride.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: ride.isDark
                        ? user.role.accent.withValues(alpha: 0.18)
                        : user.role.accentSoft,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    user.role.displayName,
                    style: TextStyle(
                      fontSize: AppText.label,
                      fontWeight: FontWeight.w800,
                      color: user.role.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PanelSwitcher(onSwitched: () => Navigator.of(context).pop()),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  AuthService.instance.signOut();
                },
                icon: const Icon(Icons.logout, size: 21),
                label: const Text('Cerrar sesión'),
                style: FilledButton.styleFrom(
                  backgroundColor: ride.isDark ? ride.dangerSoft : ride.danger,
                  foregroundColor: ride.isDark ? ride.dangerInk : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
