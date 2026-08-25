import 'package:flutter/material.dart';

import '../../core/validators.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/ride_text_field.dart';

/// Registro.
///
/// Réplica del `RegisterForm` de WEB-RIDE: el rol se elige aquí (no antes) y
/// se piden exactamente los mismos cuatro datos que `/api/register`.
class RegisterBox extends StatefulWidget {
  const RegisterBox({super.key, required this.onBack, required this.onLogin});

  final VoidCallback onBack;
  final VoidCallback onLogin;

  @override
  State<RegisterBox> createState() => _RegisterBoxState();
}

class _RegisterBoxState extends State<RegisterBox> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _role = UserRole.passenger;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
      // Al crear la cuenta la sesión queda abierta y la raíz muestra el home.
      await AuthService.instance.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        password: _passwordController.text,
        role: _role,
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
            const AuthEyebrow('CREA TU CUENTA'),
            const AuthHeading('Comienza con Ride'),
            const AuthLead('Cuéntanos cómo vas a utilizar la plataforma.'),
            RolePicker(
              value: _role,
              enabled: !_submitting,
              onChanged: (role) => setState(() {
                _role = role;
                _error = null;
              }),
            ),
            const SizedBox(height: 15),
            _TwoFields(
              first: RideTextField(
                label: 'Nombre completo',
                hint: 'Tu nombre',
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: Validators.name,
                enabled: !_submitting,
                autofillHints: const [AutofillHints.name],
              ),
              second: RideTextField(
                label: 'Teléfono',
                hint: '099 999 9999',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
                enabled: !_submitting,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
            ),
            const SizedBox(height: 15),
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
              hint: 'Mínimo 8 caracteres',
              controller: _passwordController,
              validator: Validators.password,
              textInputAction: TextInputAction.done,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.newPassword],
            ),
            if (_error != null) ...[
              const SizedBox(height: 15),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 15),
            PrimaryAction(
              label: _submitting ? 'Creando cuenta…' : 'Crear mi cuenta',
              loading: _submitting,
              onPressed: _submit,
            ),
            AuthFooter(
              text: '¿Ya tienes cuenta?',
              actionLabel: 'Inicia sesión',
              onAction: _submitting ? null : widget.onLogin,
            ),
          ],
        ),
      ),
    );
  }
}

/// `.two-fields`: dos columnas cuando hay espacio, apiladas en pantallas
/// angostas — igual que el `@media(max-width:850px)` de la web.
class _TwoFields extends StatelessWidget {
  const _TwoFields({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 15), second],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
