import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../models/user_role.dart';

/// Tarjeta de rol ("Viajo" / "Conduzco") de la pantalla de bienvenida.
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusLarge);

    return Material(
      color: selected ? role.accentSoft : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? role.accent : AppColors.border,
              width: selected ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  role.icon,
                  size: 22,
                  color: selected ? role.accent : AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      role.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role.description,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector compacto de rol en dos pestañas, usado en login y registro.
class RoleSwitch extends StatelessWidget {
  const RoleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final UserRole value;
  final ValueChanged<UserRole> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final role in UserRole.values)
            Expanded(child: _Tab(
              role: role,
              selected: role == value,
              onTap: enabled ? () => onChanged(role) : null,
            )),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.role, required this.selected, this.onTap});

  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius - 4);

    return Material(
      color: selected ? role.accentSoft : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                role.icon,
                size: 18,
                color: selected ? role.accent : AppColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                role.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.ink : AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
