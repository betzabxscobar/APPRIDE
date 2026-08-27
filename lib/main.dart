import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_colors.dart';
import 'core/app_theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/auth/first_access_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/driver_home_screen.dart';
import 'screens/home/passenger_home_screen.dart';
import 'widgets/ride_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // `runApp` va primero y sin `await` delante a propósito.
  //
  // Antes la inicialización de Supabase se esperaba aquí, antes de pintar
  // nada. Si esa llamada tardaba o fallaba, `runApp` no llegaba a ejecutarse
  // nunca y la app se quedaba en blanco de forma permanente, sin ningún
  // mensaje ni error en consola. Se reprodujo en el build web.
  //
  // Ahora la conexión ocurre dentro de [_Arranque], que muestra el progreso y
  // deja reintentar si algo sale mal.
  runApp(const RideApp());
}

/// Conecta con Supabase antes de dejar entrar a la app.
///
/// Mientras conecta muestra el logotipo; si falla, explica qué pasó y ofrece
/// reintentar. Nunca deja la pantalla en blanco.
class _Arranque extends StatefulWidget {
  const _Arranque();

  @override
  State<_Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<_Arranque> {
  bool _listo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _conectar();
  }

  Future<void> _conectar() async {
    setState(() => _error = null);
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      ).timeout(const Duration(seconds: 15));

      // La sesión guardada se restaura sola y el token se refresca solo.
      await AuthService.instance.bootstrap().timeout(
            const Duration(seconds: 15),
          );

      if (mounted) setState(() => _listo = true);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'La conexión está tardando demasiado.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos conectar con el servidor.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listo) return const AuthGate();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RideMark(size: 64),
              const SizedBox(height: 26),
              if (_error == null) ...[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Preparando Ride…',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ] else ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Revisa tu conexión a internet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _conectar,
                  child: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ride',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _Arranque(),
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
