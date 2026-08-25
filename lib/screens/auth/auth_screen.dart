import 'package:flutter/material.dart';

import '../../widgets/auth_shell.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'welcome_screen.dart';

/// Paso visible del flujo de autenticación.
///
/// Es el mismo estado `screen` que maneja `App.tsx` en WEB-RIDE: bienvenida,
/// inicio de sesión y registro viven en una sola pantalla y se intercambian
/// dentro del panel del formulario.
enum AuthStep { welcome, login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthStep _step = AuthStep.welcome;

  void _go(AuthStep step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: switch (_step) {
        AuthStep.welcome => WelcomeBox(
            key: const ValueKey(AuthStep.welcome),
            onRegister: () => _go(AuthStep.register),
            onLogin: () => _go(AuthStep.login),
          ),
        AuthStep.login => LoginBox(
            key: const ValueKey(AuthStep.login),
            onBack: () => _go(AuthStep.welcome),
            onRegister: () => _go(AuthStep.register),
          ),
        AuthStep.register => RegisterBox(
            key: const ValueKey(AuthStep.register),
            onBack: () => _go(AuthStep.welcome),
            onLogin: () => _go(AuthStep.login),
          ),
      },
    );
  }
}
