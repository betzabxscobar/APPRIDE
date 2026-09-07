import 'package:flutter/material.dart';

import '../../core/ride_colors.dart';
import '../../core/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_text_field.dart';

/// Poner una contraseña nueva tras llegar por el enlace de «olvidé mi
/// contraseña».
///
/// Aparece sola, antes que cualquier otra pantalla, en cuanto la sesión entra
/// por ese enlace. **No pide la contraseña actual**: quien llega aquí no la
/// sabe, que es todo el motivo del correo.
///
/// Tampoco se puede saltar. Quien abrió el enlace entró sin escribir ninguna
/// clave, así que dejarle usar la app sin poner una dejaría la cuenta abierta
/// para cualquiera que tenga ese correo delante. La única salida es poner la
/// contraseña o cerrar sesión.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService.instance.establecerContrasenaNueva(_nueva.text);
      // No hay que navegar: al bajar la bandera, la raíz de la app reconstruye
      // sola y lleva a la pantalla que le toque por su rol.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Scaffold(
      backgroundColor: ride.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_reset, size: 46, color: ride.accent),
                    const SizedBox(height: 18),
                    Text(
                      'Pon tu contraseña nueva',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: ride.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Entraste desde el enlace del correo. Elige una clave y '
                      'con esa entrarás a partir de ahora.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: ride.inkMuted),
                    ),
                    const SizedBox(height: 26),
                    RidePasswordField(
                      label: 'Contraseña nueva',
                      controller: _nueva,
                      enabled: !_guardando,
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 14),
                    RidePasswordField(
                      label: 'Repítela',
                      controller: _repetir,
                      enabled: !_guardando,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          Validators.confirmPassword(v, _nueva.text),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _guardando ? null : _guardar,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(_guardando ? 'Guardando…' : 'Guardar y entrar'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _guardando
                          ? null
                          : () => AuthService.instance.signOut(),
                      child: const Text('Cancelar y salir'),
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
