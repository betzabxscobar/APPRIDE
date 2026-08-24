import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/validators.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_logo.dart';
import '../../widgets/ride_text_field.dart';

/// Primer acceso administrativo: obliga a reemplazar la contraseña temporal
/// antes de entrar al panel. Es el equivalente del `FirstAccessForm` de
/// WEB-RIDE y consume el mismo flujo de `/api/change-password`.
class FirstAccessScreen extends StatefulWidget {
  const FirstAccessScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<FirstAccessScreen> createState() => _FirstAccessScreenState();
}

class _FirstAccessScreenState extends State<FirstAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await AuthService.instance.changeInitialPassword(
        _passwordController.text,
      );
      // La raíz de la app reacciona al cambio y muestra el panel.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.welcomeGradient),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                const Center(child: RideMark(size: 52)),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppColors.purpleSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.purple,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'PRIMER ACCESO ADMINISTRATIVO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Crea tu contraseña personal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hola, ${widget.user.name}. Por seguridad debes reemplazar '
                  'la contraseña temporal antes de entrar al panel.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 28),
                RidePasswordField(
                  label: 'Nueva contraseña',
                  hint: 'Mínimo 10 caracteres',
                  controller: _passwordController,
                  validator: Validators.adminPassword,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                RidePasswordField(
                  label: 'Confirmar contraseña',
                  hint: 'Repite tu contraseña',
                  controller: _confirmController,
                  validator: (v) => Validators.confirmPassword(
                    v,
                    _passwordController.text,
                  ),
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const ButtonSpinner()
                      : const Text('Guardar y entrar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : _signOut,
                  child: const Text('Cerrar sesión'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.inkMuted,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'La contraseña temporal deja de funcionar apenas '
                          'guardes la nueva.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
