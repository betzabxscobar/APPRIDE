import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/panel_switcher.dart';

/// Hoja inferior con el perfil, el cambio de rol y el cierre de sesión.
Future<void> showAccountSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _AccountSheet(user: user),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: user.role.accentSoft,
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      fontSize: 16,
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: user.role.accentSoft,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    user.role.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: user.role.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PanelSwitcher(onSwitched: () => Navigator.of(context).pop()),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                AuthService.instance.signOut();
              },
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Cerrar sesión'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
