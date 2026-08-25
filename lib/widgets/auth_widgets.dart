import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../models/user_role.dart';

/// Tarjeta que contiene un formulario de autenticación (`.auth-box`).
///
/// Aparece con la misma animación de entrada que la web:
/// `translateY(12px) scale(.99)` → posición final en 450 ms.
class AuthCard extends StatefulWidget {
  const AuthCard({super.key, required this.children});

  final List<Widget> children;

  @override
  State<AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends State<AuthCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - _curve.value)),
          child: Transform.scale(
            scale: 0.99 + 0.01 * _curve.value,
            child: child,
          ),
        ),
        // `width: min(100%,450px)`: el ancho debe ser explícito para que los
        // hijos (botones, campos) ocupen toda la tarjeta.
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth.isFinite
                ? math.min(constraints.maxWidth, AppTheme.authBoxWidth)
                : AppTheme.authBoxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta pequeña sobre el título (`.eyebrow`).
class AuthEyebrow extends StatelessWidget {
  const AuthEyebrow(this.text, {super.key, this.color = AppColors.eyebrow});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: color,
      ),
    );
  }
}

/// Título del formulario (`.auth-box h2`).
class AuthHeading extends StatelessWidget {
  const AuthHeading(this.text, {super.key, this.size = 36});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: AppTheme.display(size)),
    );
  }
}

/// Bajada del formulario (`.auth-box > p`).
class AuthLead extends StatelessWidget {
  const AuthLead(this.text, {super.key, this.bottomSpacing = 28});

  final String text;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}

/// Botón principal con degradado y flecha a la derecha (`.primary-action`).
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.showArrow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(AppTheme.radiusAction);

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryAction,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              child: SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (showArrow)
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '→',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón secundario blanco con borde (`.secondary-action`).
class SecondaryAction extends StatelessWidget {
  const SecondaryAction({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusAction);

    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF24394A),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace "← Volver" (`.back`).
class BackLink extends StatelessWidget {
  const BackLink({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.only(right: 8, bottom: 4),
          child: Text(
            '← Volver',
            style: TextStyle(fontSize: 12, color: AppColors.backLink),
          ),
        ),
      ),
    );
  }
}

/// Pie del formulario: texto gris + enlace (`.form-footer`).
class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.text,
    required this.actionLabel,
    this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$text ',
            style: const TextStyle(fontSize: 11, color: AppColors.footerText),
          ),
          InkWell(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.link,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector de rol del registro (`.role-picker`): "Viajo" y "Conduzco".
class RolePicker extends StatelessWidget {
  const RolePicker({
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
    // `IntrinsicHeight` iguala el alto de las dos tarjetas, como hace la
    // cuadrícula de la web, sin pedir alto infinito dentro del scroll.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final role in UserRole.selectable) ...[
            Expanded(
              child: _RoleOption(
                role: role,
                selected: role == value,
                onTap: enabled ? () => onChanged(role) : null,
              ),
            ),
            if (role != UserRole.selectable.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.selected, this.onTap});

  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(11);

    return Material(
      color: selected ? AppColors.primarySoft : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                role.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF243B4C),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                role.description,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: AppColors.rolePickerHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
