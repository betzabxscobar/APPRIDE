import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';
import 'ride_logo.dart';

/// Estructura de las pantallas de autenticación, igual que `.auth-page` en
/// WEB-RIDE: panel de marca oscuro a la izquierda y panel del formulario a la
/// derecha. Bajo 850 px de ancho el panel de marca se oculta y solo queda la
/// marca pequeña arriba a la izquierda, tal como hace el `@media` de la web.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppTheme.wideBreakpoint;

          if (!wide) return _FormPanel(compact: true, child: child);

          return Row(
            children: [
              // minmax(420px,1.05fr) minmax(480px,.95fr)
              Expanded(flex: 105, child: const BrandPanel()),
              Expanded(flex: 95, child: _FormPanel(child: child)),
            ],
          );
        },
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.formPanel),
      child: SafeArea(
        child: compact
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RideWordmark(markSize: 35, fontSize: 22),
                    const SizedBox(height: 38),
                    child,
                  ],
                ),
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 40,
                  ),
                  child: Center(child: child),
                ),
              ),
      ),
    );
  }
}

/// Columna oscura de la izquierda (`.brand-panel`).
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/FondoObscuroRide.png',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
