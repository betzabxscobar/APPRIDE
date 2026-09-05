import 'package:flutter/material.dart';

import '../../core/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/ride_text_field.dart';

/// Inicio de sesión.
///
/// Mismos campos, textos y mensajes que el `AuthForm` de WEB-RIDE: correo y
/// contraseña, sin selección de rol (el rol lo determina la cuenta).
class LoginBox extends StatefulWidget {
  const LoginBox({
    super.key,
    required this.onBack,
    required this.onRegister,
    required this.onForgotPassword,
  });

  final VoidCallback onBack;
  final VoidCallback onRegister;
  final VoidCallback onForgotPassword;

  @override
  State<LoginBox> createState() => _LoginBoxState();
}

class _LoginBoxState extends State<LoginBox> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
      // La raíz de la app reacciona a la sesión y muestra el home o el panel.
      await AuthService.instance.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: AuthCard(
          children: [
            BackLink(onPressed: _submitting ? null : widget.onBack),
            const SizedBox(height: 26),
            const AuthEyebrow('ACCESO SEGURO'),
            const SizedBox(height: 20),
            const AuthHeading('Qué bueno verte'),
            const AuthLead('Ingresa tus datos para continuar.'),
            const SizedBox(height: 10),
            RideTextField(
              label: 'Correo electrónico',
              hint: 'nombre@correo.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 15),
            RidePasswordField(
              label: 'Contraseña',
              hint: 'Tu contraseña',
              controller: _passwordController,
              validator: (v) => Validators.required(v, campo: 'La contraseña'),
              textInputAction: TextInputAction.done,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.password],
            ),
            if (_error != null) ...[
              const SizedBox(height: 15),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 15),
            PrimaryAction(
              label: _submitting ? 'Ingresando…' : 'Iniciar sesión',
              loading: _submitting,
              onPressed: _submit,
              backgroundColor: const Color(0xFF81D4FA),
              foregroundColor: Colors.black,
              border: const BorderSide(color: Colors.black, width: 2),
              showShadow: false,
            ),
            Center(
              child: TextButton(
                onPressed: _submitting ? null : widget.onForgotPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
            AuthFooter(
              text: '¿Aún no tienes cuenta?',
              actionLabel: 'Regístrate',
              onAction: _submitting ? null : widget.onRegister,
            ),
          ],
        ),
      ),
    );
  }
}
