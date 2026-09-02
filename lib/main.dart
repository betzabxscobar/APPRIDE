import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/preferencias.dart';
import 'core/ride_colors.dart';
import 'core/supabase_config.dart';
import 'core/theme_controller.dart';
import 'services/auth_service.dart';
import 'services/trip_session_store.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/auth/first_access_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/driver_home_screen.dart';
import 'screens/home/passenger_home_screen.dart';
import 'screens/home/welcome_home_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'widgets/ride_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lo único que se espera antes de pintar son las preferencias del teléfono,
  // que es una lectura local y no sale a la red. Tiene que ir antes porque de
  // ahí sale el tema: leerlo después haría que la app arrancase en claro y
  // saltase a oscuro en el primer frame, que es justo lo que se nota.
  //
  // Nunca bloquea de verdad: `cargar` se traga sus propios fallos y lleva
  // tope de tiempo.
  await Preferencias.instance.cargar();
  ThemeController.instance.cargar();

  // `runApp` va sin `await` de Supabase delante a propósito.
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

      // El viaje guardado se lee DESPUÉS del perfil, no antes.
      //
      // Comprueba que sea de la cuenta que está entrando, y para eso hace
      // falta saber quién es. Leerlo en `main()` —donde estaba— significaba
      // preguntarlo con la sesión todavía sin cargar: el dueño salía nulo y el
      // viaje se descartaba siempre, justo lo contrario de lo que hace falta.
      TripSessionStore.instance.cargar();

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
    if (_listo) return const _AppRoot();

    final ride = context.ride;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RideMark(size: 76),
                const SizedBox(height: 30),
                if (_error == null) ...[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Preparando Ride…',
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: ride.inkMuted,
                    ),
                  ),
                ] else ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTheme.display(
                      AppText.h2,
                      color: ride.ink,
                      letterSpacing: -0.6,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Revisa tu conexión a internet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppText.small,
                      height: 1.5,
                      color: ride.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _conectar,
                    child: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
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
    // El tema puede cambiar en cualquier momento desde Configuración, así que
    // el MaterialApp entero escucha a [ThemeController]. Por defecto sigue
    // siendo el ajuste del teléfono, que es lo que la gente espera en móvil;
    // lo que hay ahora es la posibilidad de fijarlo.
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'Ride',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeController.instance.mode,
        home: const _Arranque(),
      ),
    );
  }
}

/// Muestra el splash la primera vez y luego el AuthGate.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _showSplash = true;

  /// La bienvenida es para quien todavía no ha entrado.
  ///
  /// Antes se mostraba siempre, también a quien ya tenía la sesión abierta: al
  /// reabrir la app había que pasar por una pantalla de presentación y tocar
  /// «continuar» para volver a lo que se estaba haciendo. Con un viaje en
  /// marcha eso es exactamente lo que no puede pasar.
  late final bool _mostrarBienvenida = !AuthService.instance.isAuthenticated;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onDone: () => setState(() => _showSplash = false),
      );
    }

    if (!_mostrarBienvenida) return const AuthGate();

    return WelcomeHomeScreen(
      onContinue: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      },
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
