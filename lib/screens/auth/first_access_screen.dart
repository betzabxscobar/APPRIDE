import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/validators.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/ride_logo.dart';
import '../../widgets/ride_text_field.dart';

/// Primer acceso administrativo: obliga a reemplazar la contraseña temporal
/// antes de entrar al panel. Es el equivalente del `FirstAccessForm` de
/// WEB-RIDE y aplica las mismas reglas que `/api/change-password`.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandPanel),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3D000000),
                          blurRadius: 70,
                          offset: Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: RideWordmark(markSize: 37, fontSize: 22),
                          ),
                          const SizedBox(height: 30),
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.greenSoft,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Center(
                              child: Text(
                                '◇',
                                style: TextStyle(
                                  fontSize: 25,
                                  color: Color(0xFF1BA68C),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const AuthEyebrow(
                            'PRIMER ACCESO ADMINISTRATIVO',
                            color: Color(0xFF188CB7),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 12),
                            child: Text(
                              'Crea tu contraseña personal',
                              style: AppTheme.display(30, height: 1.2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Text(
                              'Hola, ${widget.user.name}. Por seguridad debes '
                              'reemplazar la contraseña temporal antes de '
                              'entrar al panel.',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                          RidePasswordField(
                            label: 'Nueva contraseña',
                            hint: 'Mínimo 10 caracteres',
                            controller: _passwordController,
                            validator: Validators.adminPassword,
                            enabled: !_submitting,
                          ),
                          const SizedBox(height: 15),
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
                          if (_error != null) ...[
                            const SizedBox(height: 15),
                            ErrorBanner(message: _error!),
                          ],
                          const SizedBox(height: 15),
                          PrimaryAction(
                            label: _submitting
                                ? 'Guardando…'
                                : 'Guardar y entrar',
                            loading: _submitting,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: InkWell(
                              onTap: _submitting
                                  ? null
                                  : () => AuthService.instance.signOut(),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Text(
                                  'Cerrar sesión',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF748491),
                                  ),
                                ),
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
          ),
        ),
      ),
    );
  }
}
