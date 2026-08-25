import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride/main.dart';
import 'package:ride/models/user_role.dart';
import 'package:ride/screens/auth/auth_screen.dart';
import 'package:ride/services/auth_service.dart';
import 'package:ride/widgets/auth_shell.dart';

/// Credenciales del equipo administrativo, leídas de las mismas variables de
/// compilación que usa [AuthService]. Quedan vacías si las pruebas se corren
/// sin `--dart-define-from-file=config/credenciales-administrativas.json`, y
/// entonces los casos que dependen de ellas se marcan como omitidos.
const _equipo = <String, (String, UserRole)>{
  'betzabxscobar@gmail.com': (
    String.fromEnvironment('RIDE_ADMIN_BETZABE'),
    UserRole.superadmin,
  ),
  'dandreszurtaf23@gmail.com': (
    String.fromEnvironment('RIDE_ADMIN_DIEGO'),
    UserRole.superadmin,
  ),
  'alexyanez1119@gmail.com': (
    String.fromEnvironment('RIDE_ADMIN_ALEX'),
    UserRole.admin,
  ),
  'mayuriremache0@gmail.com': (
    String.fromEnvironment('RIDE_ADMIN_MAYURI'),
    UserRole.admin,
  ),
  'javierconforme18@gmail.com': (
    String.fromEnvironment('RIDE_ADMIN_JAVIER'),
    UserRole.admin,
  ),
};

const _sinCredenciales =
    'Corre las pruebas con --dart-define-from-file='
    'config/credenciales-administrativas.json';

void main() {
  /// Cuentas del equipo que sí traen contraseña en esta compilación.
  final configuradas = _equipo.entries
      .where((entrada) => entrada.value.$1.isNotEmpty)
      .toList();

  /// Primera cuenta configurada con el rol pedido, si existe.
  MapEntry<String, (String, UserRole)>? cuentaCon(UserRole role) {
    for (final entrada in configuradas) {
      if (entrada.value.$2 == role) return entrada;
    }
    return null;
  }

  tearDown(() async {
    await AuthService.instance.signOut();
  });

  /// Espera a que termine una llamada al servicio de autenticación.
  ///
  /// El botón principal no lleva spinner (la web solo cambia el texto), así
  /// que no hay animación que haga avanzar el reloj: hay que adelantarlo a
  /// mano por encima de la latencia simulada del servicio.
  Future<void> esperarRespuesta(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  /// Lleva la pantalla de autenticación desde la bienvenida hasta [step].
  Future<void> abrir(WidgetTester tester, AuthStep step) async {
    await tester.pumpWidget(const RideApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.text(step == AuthStep.login ? 'Ya tengo una cuenta' : 'Crear cuenta'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('La bienvenida ofrece registro e inicio de sesión',
      (tester) async {
    await tester.pumpWidget(const RideApp());
    await tester.pumpAndSettle();

    expect(find.text('BIENVENIDO A RIDE'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Ya tengo una cuenta'), findsOneWidget);
  });

  testWidgets('El panel de marca solo aparece en pantallas anchas',
      (tester) async {
    // En móvil (800 px de ancho por defecto) la columna oscura se oculta,
    // igual que el `@media(max-width:850px)` de WEB-RIDE.
    await tester.pumpWidget(const RideApp());
    await tester.pumpAndSettle();
    expect(find.byType(BrandPanel), findsNothing);

    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const RideApp());
    await tester.pumpAndSettle();
    expect(find.byType(BrandPanel), findsOneWidget);

    // El formulario sigue funcionando junto al panel de marca.
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Comienza con Ride'), findsOneWidget);
  });

  testWidgets('Login de pasajero lleva al home de pasajero', (tester) async {
    await abrir(tester, AuthStep.login);

    expect(find.text('Qué bueno verte'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'pasajero@ride.app',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Ride1234');
    await tester.tap(find.text('Iniciar sesión'));
    await esperarRespuesta(tester);

    expect(find.textContaining('¡Hola, Andrea!'), findsOneWidget);
  });

  testWidgets('El registro pide los mismos datos que la web', (tester) async {
    await abrir(tester, AuthStep.register);

    expect(find.text('Comienza con Ride'), findsOneWidget);
    // El rol se elige aquí, no antes: es el `.role-picker` de WEB-RIDE.
    expect(find.text('Viajo'), findsOneWidget);
    expect(find.text('Conduzco'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Nombre completo'), findsOneWidget);
    expect(find.text('Teléfono'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });

  testWidgets('Registrarse como conductor abre el home de conductor',
      (tester) async {
    await abrir(tester, AuthStep.register);

    await tester.tap(find.text('Conduzco'));
    await tester.pump();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Marta Peña');
    await tester.enterText(campos.at(1), '0990001122');
    await tester.enterText(campos.at(2), 'marta.pena@ride.app');
    await tester.enterText(campos.at(3), 'RideSegura1');

    // El formulario completo no cabe en el alto del test: hay que traer el
    // botón a la vista antes de tocarlo.
    final crear = find.text('Crear mi cuenta');
    await tester.ensureVisible(crear);
    await tester.pumpAndSettle();
    await tester.tap(crear);
    await esperarRespuesta(tester);

    expect(find.text('Modo conductor'), findsOneWidget);
  });

  testWidgets('El home de conductor muestra las oportunidades',
      (tester) async {
    // Sin await: el retardo simulado del servicio avanza con el reloj falso
    // del test, que solo corre durante los pump().
    final pendingSignIn = AuthService.instance.signIn(
      email: 'conductor@ride.app',
      password: 'Ride1234',
    );

    await tester.pumpWidget(const RideApp());
    await esperarRespuesta(tester);
    await pendingSignIn;

    expect(find.text('Modo conductor'), findsOneWidget);
    expect(find.text('Toyota Corolla · 2021'), findsOneWidget);
    expect(find.text('PDC-1234'), findsOneWidget);

    await tester.dragUntilVisible(
      find.widgetWithText(FilledButton, 'Aceptar ruta').first,
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Aceptar ruta'), findsWidgets);
  });

  test('Login rechaza una contraseña incorrecta', () async {
    await expectLater(
      AuthService.instance.signIn(
        email: 'pasajero@ride.app',
        password: 'incorrecta',
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('No se puede registrar dos veces el mismo correo', () async {
    await expectLater(
      AuthService.instance.register(
        name: 'Andrea Salazar',
        email: 'PASAJERO@ride.app',
        phone: '0991234567',
        password: 'Ride1234',
        role: UserRole.passenger,
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('Cada cuenta del equipo entra con su credencial y su rol', () async {
    for (final entrada in configuradas) {
      final (password, role) = entrada.value;
      final user = await AuthService.instance.signIn(
        email: entrada.key,
        password: password,
      );

      expect(user.role, role, reason: entrada.key);
      // Sin base de datos no hay cambio de contraseña: entran directo.
      expect(user.mustChangePassword, isFalse, reason: entrada.key);
      await AuthService.instance.signOut();
    }
  }, skip: configuradas.isEmpty ? _sinCredenciales : null);

  test('La credencial de una cuenta no sirve para otra', () async {
    final primera = configuradas.first;
    final segunda = configuradas.last;

    await expectLater(
      AuthService.instance.signIn(
        email: primera.key,
        password: segunda.value.$1,
      ),
      throwsA(isA<AuthException>()),
    );
  }, skip: configuradas.length < 2 ? _sinCredenciales : null);

  test('Un admin no ve a los superadmin; un superadmin sí', () async {
    final admin = cuentaCon(UserRole.admin)!;
    final superadmin = cuentaCon(UserRole.superadmin)!;

    await AuthService.instance.signIn(
      email: admin.key,
      password: admin.value.$1,
    );
    final desdeAdmin = AuthService.instance.visibleUsers();
    expect(desdeAdmin.any((user) => user.role.isSuperadmin), isFalse);
    expect(desdeAdmin.any((user) => user.email == admin.key), isTrue);

    await AuthService.instance.signOut();

    await AuthService.instance.signIn(
      email: superadmin.key,
      password: superadmin.value.$1,
    );
    expect(
      AuthService.instance.visibleUsers().any((user) => user.role.isSuperadmin),
      isTrue,
    );
  },
      skip: cuentaCon(UserRole.admin) == null ||
              cuentaCon(UserRole.superadmin) == null
          ? _sinCredenciales
          : null);

  test('El cambio de contraseña sigue exigiendo 10 caracteres', () async {
    // El flujo no se usa todavía, pero la regla debe seguir vigente para
    // cuando la base de datos permita guardar la contraseña definitiva.
    final cuenta = configuradas.first;
    await AuthService.instance.signIn(
      email: cuenta.key,
      password: cuenta.value.$1,
    );

    await expectLater(
      AuthService.instance.changeInitialPassword('Corta123'),
      throwsA(isA<AuthException>()),
    );
  }, skip: configuradas.isEmpty ? _sinCredenciales : null);
}
