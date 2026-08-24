import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/validators.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_logo.dart';
import '../../widgets/ride_text_field.dart';
import '../../widgets/role_selector.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.role});

  /// Rol elegido en la bienvenida; se puede cambiar desde el selector.
  final UserRole role;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late UserRole _role = widget.role;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
      await AuthService.instance.signIn(
        email: _emailController.text,
        password: _passwordController.text,
        expectedRole: _role,
      );
      if (!mounted) return;
      // La raíz de la app ya decide el home según el rol: limpiamos la pila.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RegisterScreen(role: _role)),
    );
  }

  void _onForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recuperación de contraseña: pendiente de implementar'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Iniciar sesión'),
      ),
      body: SafeArea(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                const Center(child: RideMark(size: 52)),
                const SizedBox(height: 20),
                const Text(
                  'Bienvenido de vuelta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Entra como ${_role.displayName.toLowerCase()} para continuar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 24),
                RoleSwitch(
                  value: _role,
                  enabled: !_submitting,
                  onChanged: (role) => setState(() {
                    _role = role;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 24),
                RideTextField(
                  label: 'Correo electrónico',
                  hint: 'tu@correo.com',
                  icon: Icons.mail_outline,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  enabled: !_submitting,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 16),
                RidePasswordField(
                  label: 'Contraseña',
                  hint: 'Tu contraseña',
                  controller: _passwordController,
                  validator: (v) =>
                      Validators.required(v, campo: 'La contraseña'),
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onSubmitted: (_) => _submit(),
                  autofillHints: const [AutofillHints.password],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting ? null : _onForgotPassword,
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ] else
                  const SizedBox(height: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const ButtonSpinner()
                      : const Text('Iniciar sesión'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '¿No tienes cuenta?',
                      style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _goToRegister,
                      child: const Text('Regístrate'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _DemoCredentials(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuentas de prueba mientras la autenticación es local.
class _DemoCredentials extends StatelessWidget {
  const _DemoCredentials();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuentas de prueba',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Pasajero: pasajero@ride.app\n'
            'Conductor: conductor@ride.app\n'
            'Contraseña: Ride1234',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.inkMuted,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Equipo administrativo',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Entra con el correo de tu cuenta admin o superadmin.\n'
            'Contraseña temporal: ${AuthService.temporaryAdminPassword}\n'
            'Al primer ingreso se pide una contraseña definitiva.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
