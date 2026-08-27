import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../models/user_role.dart';

/// Contenedor de un formulario de autenticación.
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
        // El ancho debe ser explícito para que los hijos (botones, campos)
        // ocupen toda la columna.
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
  const AuthEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppText.micro,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: color ?? context.ride.accent,
      ),
    );
  }
}

/// Título del formulario.
class AuthHeading extends StatelessWidget {
  const AuthHeading(this.text, {super.key, this.size = AppText.h1});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Text(
        text,
        style: AppTheme.display(
          size,
          color: context.ride.ink,
          letterSpacing: -0.9,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Bajada del formulario.
class AuthLead extends StatelessWidget {
  const AuthLead(this.text, {super.key, this.bottomSpacing = 26});

  final String text;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppText.body,
          height: 1.5,
          color: context.ride.inkMuted,
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
    final ride = context.ride;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(AppTheme.radiusAction);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryAction,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: ride.isDark ? 0.4 : 0.3),
              blurRadius: 24,
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
            child: SizedBox(
              height: AppTheme.tapTarget,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: AppText.body,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : showArrow
                              ? const Text(
                                  '→',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                )
                              : const SizedBox.shrink(),
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

/// Botón secundario con borde (`.secondary-action`).
class SecondaryAction extends StatelessWidget {
  const SecondaryAction({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final radius = BorderRadius.circular(AppTheme.radiusAction);

    return Material(
      color: ride.surfaceAlt,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Container(
          height: AppTheme.tapTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: ride.border, width: 1.4),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.body,
              fontWeight: FontWeight.w800,
              color: ride.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace "← Volver" (`.back`).
///
/// Con área de toque propia: como texto suelto de 12 px era de los controles
/// más difíciles de acertar de toda la app.
class BackLink extends StatelessWidget {
  const BackLink({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onPressed,
          iconSize: 22,
          color: ride.inkMuted,
          tooltip: 'Volver',
          style: IconButton.styleFrom(
            backgroundColor: ride.surfaceAlt,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
    );
  }
}

/// Pie del formulario: texto + enlace (`.form-footer`).
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
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            text,
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
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
    // `IntrinsicHeight` iguala el alto de las dos tarjetas sin pedir alto
    // infinito dentro del scroll.
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
            if (role != UserRole.selectable.last) const SizedBox(width: 12),
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
    final ride = context.ride;
    final radius = BorderRadius.circular(AppTheme.radiusAction);
    final accent = selected ? ride.accent : ride.inkMuted;

    return Material(
      color: selected ? ride.accentSoft : ride.surfaceAlt,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? ride.accent : ride.border,
              width: selected ? 1.8 : 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(role.icon, size: 22, color: accent),
              const SizedBox(height: 10),
              Text(
                role.label,
                style: TextStyle(
                  fontSize: AppText.h3,
                  fontWeight: FontWeight.w800,
                  color: selected ? ride.accent : ride.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                role.description,
                style: TextStyle(
                  fontSize: AppText.label,
                  height: 1.35,
                  color: ride.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
