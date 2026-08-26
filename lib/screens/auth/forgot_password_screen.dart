import 'package:flutter/material.dart';

import '../../core/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/ride_text_field.dart';

/// Recuperación de contraseña: paso 1, pedir el enlace por correo.
///
/// Es el equivalente del `ForgotPasswordForm` de WEB-RIDE y comparte su
/// aspecto: misma tarjeta, mismos textos.
///
/// El paso 2 (fijar la contraseña nueva) ocurre en el navegador, porque el
/// enlace del correo no abre la app. Al volver, se inicia sesión aquí con la
/// contraseña nueva.
class ForgotPasswordBox extends StatefulWidget {
  const ForgotPasswordBox({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<ForgotPasswordBox> createState() => _ForgotPasswordBoxState();
}

class _ForgotPasswordBoxState extends State<ForgotPasswordBox> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _submitting = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    try {
      await AuthService.instance.requestPasswordReset(_emailController.text);
      if (!mounted) return;
      // Mismo aviso exista o no la cuenta: no se filtra qué correos hay.
      setState(() {
        _notice = 'Si ese correo tiene una cuenta, te enviamos el enlace. '
            'Ábrelo para crear tu contraseña nueva y vuelve aquí a entrar.';
      });
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
            const AuthEyebrow('RECUPERAR ACCESO'),
            const AuthHeading('¿Olvidaste tu contraseña?'),
            const AuthLead(
              'Escribe tu correo y te enviamos un enlace para crear una nueva.',
            ),
            RideTextField(
              label: 'Correo electrónico',
              hint: 'nombre@correo.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              enabled: !_submitting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.email],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 15),
              NoticeBanner(message: _notice!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 15),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 15),
            PrimaryAction(
              label: _submitting ? 'Enviando…' : 'Enviar enlace',
              loading: _submitting,
              onPressed: _submit,
            ),
            AuthFooter(
              text: '¿Ya la recordaste?',
              actionLabel: 'Inicia sesión',
              onAction: _submitting ? null : widget.onBack,
            ),
          ],
        ),
      ),
    );
  }
}
