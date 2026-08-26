import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/auth/first_access_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/driver_home_screen.dart';
import 'screens/home/passenger_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La sesion queda guardada en el dispositivo: al reabrir la app se restaura
  // sola y el token se refresca solo.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await AuthService.instance.bootstrap();

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
/// Mientras no hay sesión se muestra [AuthScreen], que alterna bienvenida,
/// login y registro dentro de la misma pantalla igual que `App.tsx` en
/// WEB-RIDE. Al autenticarse, [AuthService] notifica y esta raíz reconstruye
/// con el usuario listo. La sesión se restaura en `main()` antes del primer
/// frame, así que aquí no hace falta pantalla de carga.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;

        if (user == null) return const AuthScreen();

        // Cuentas administrativas: primero la contraseña definitiva, después
        // el panel. Es el mismo orden que aplica WEB-RIDE.
        if (user.role.isAdministrative && user.mustChangePassword) {
          return FirstAccessScreen(key: ValueKey('first-${user.id}'), user: user);
        }

        // La pantalla la decide la vista activa, no el rol: un administrador
        // puede estar mirando la interfaz de pasajero o de conductor. El rol
        // real de la cuenta no cambia nunca.
        final view = AuthService.instance.activeView;

        if (view.isAdministrative) {
          return AdminDashboardScreen(
            key: ValueKey('admin-${user.id}-${view.id}'),
            user: user,
            viewAs: view,
          );
        }

        return view.isDriver
            ? DriverHomeScreen(key: ValueKey('driver-${user.id}'), user: user)
            : PassengerHomeScreen(key: ValueKey('passenger-${user.id}'), user: user);
      },
    );
  }
}
