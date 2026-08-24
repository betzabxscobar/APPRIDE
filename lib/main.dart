import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/home/driver_home_screen.dart';
import 'screens/home/passenger_home_screen.dart';

void main() {
  runApp(const RideApp());
}

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ride',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}

/// Decide qué pantalla mostrar según la sesión y el rol activo.
///
/// Las pantallas de login/registro se abren encima de [WelcomeScreen] y al
/// autenticarse hacen `popUntil(isFirst)`, de modo que esta raíz vuelve a
/// construirse ya con el usuario listo.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;

        if (user == null) return const WelcomeScreen();

        return user.role.isDriver
            ? DriverHomeScreen(key: ValueKey(user.id), user: user)
            : PassengerHomeScreen(key: ValueKey(user.id), user: user);
      },
    );
  }
}
