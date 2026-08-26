import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride/main.dart';
import 'package:ride/models/app_user.dart';
import 'package:ride/models/user_role.dart';
import 'package:ride/models/vehicle.dart';
import 'package:ride/screens/auth/auth_screen.dart';
import 'package:ride/services/auth_service.dart';
import 'package:ride/widgets/auth_shell.dart';

/// Pruebas de la app tras conectar Supabase.
///
/// La versión anterior de este archivo probaba el login, el registro y la
/// visibilidad por rol contra el almacén de cuentas en memoria que tenía
/// `AuthService` (`pasajero@ride.app` / `Ride1234` y las credenciales del
/// equipo leídas con `--dart-define`). Ese almacén ya no existe: ahora todo
/// pasa por Supabase Auth.
///
/// Esos casos no se pueden reescribir aquí sin salir a la red y sin crear
/// usuarios reales en el proyecto de producción, así que se retiraron en vez
/// de dejarlos fallando o marcados como omitidos. Para recuperarlos hace falta
/// un proyecto Supabase de pruebas con cuentas semilla y correrlos como
/// prueba de integración, no como prueba unitaria.
///
/// Lo que queda cubierto aquí es lo que sí se puede verificar sin red: el
/// árbol de widgets de la pantalla de autenticación y la lógica pura de los
/// modelos.
void main() {
  group('Pantalla de autenticación', () {
    /// Lleva la pantalla desde la bienvenida hasta [step].
    Future<void> abrir(WidgetTester tester, AuthStep step) async {
      await tester.pumpWidget(const RideApp());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text(
          step == AuthStep.login ? 'Ya tengo una cuenta' : 'Crear cuenta',
        ),
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

    testWidgets('El login pide correo y contraseña', (tester) async {
      await abrir(tester, AuthStep.login);

      expect(find.text('Qué bueno verte'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
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

    testWidgets('Desde el login se llega a recuperar la contraseña',
        (tester) async {
      await abrir(tester, AuthStep.login);

      final enlace = find.text('¿Olvidaste tu contraseña?');
      expect(enlace, findsOneWidget);

      await tester.ensureVisible(enlace);
      await tester.pumpAndSettle();
      await tester.tap(enlace);
      await tester.pumpAndSettle();

      expect(find.text('RECUPERAR ACCESO'), findsOneWidget);
      // Solo pide el correo: la contraseña nueva se fija desde el enlace.
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Enviar enlace'), findsOneWidget);
    });

    testWidgets('El registro no ofrece roles administrativos', (tester) async {
      await abrir(tester, AuthStep.register);

      // Estos dos existen en el enum pero nunca se muestran: las cuentas
      // administrativas las provisiona el equipo, no el formulario público.
      expect(find.text('Administro'), findsNothing);
      expect(find.text('Superadmin'), findsNothing);
    });
  });

  group('Roles', () {
    test('Solo pasajero y conductor se pueden elegir', () {
      expect(UserRole.selectable, [UserRole.passenger, UserRole.driver]);
    });

    test('admin y superadmin son administrativos; los demás no', () {
      expect(UserRole.admin.isAdministrative, isTrue);
      expect(UserRole.superadmin.isAdministrative, isTrue);
      expect(UserRole.passenger.isAdministrative, isFalse);
      expect(UserRole.driver.isAdministrative, isFalse);
    });

    test('fromId acepta los cuatro valores del enum de la base', () {
      // Son los mismos que `public.user_role` en Postgres.
      expect(UserRole.fromId('passenger'), UserRole.passenger);
      expect(UserRole.fromId('driver'), UserRole.driver);
      expect(UserRole.fromId('admin'), UserRole.admin);
      expect(UserRole.fromId('superadmin'), UserRole.superadmin);
    });

    test('Un rol desconocido cae a pasajero, nunca a administrativo', () {
      expect(UserRole.fromId('dios'), UserRole.passenger);
      expect(UserRole.fromId(''), UserRole.passenger);
    });
  });

  group('AppUser', () {
    AppUser usuario({String name = 'Andrea Salazar'}) => AppUser(
          id: 'u-1',
          name: name,
          email: 'andrea@ride.app',
          phone: '0991234567',
          role: UserRole.passenger,
        );

    test('firstName toma solo el primer nombre', () {
      expect(usuario().firstName, 'Andrea');
    });

    test('initials usa las dos primeras palabras', () {
      expect(usuario().initials, 'AS');
      expect(usuario(name: 'Andrea').initials, 'A');
    });

    test('copyWith conserva la identidad y cambia solo lo pedido', () {
      final original = usuario();
      final cambiado = original.copyWith(
        role: UserRole.driver,
        vehicle: const Vehicle(model: 'Kia Rio', plate: 'ABC-1234', year: 2022),
      );

      expect(cambiado.id, original.id);
      expect(cambiado.email, original.email);
      expect(cambiado.role, UserRole.driver);
      expect(cambiado.vehicle?.plate, 'ABC-1234');
    });
  });

  group('AuthService', () {
    test('El registro rechaza roles administrativos antes de salir a la red',
        () async {
      // La validación es local, así que no necesita sesión ni conexión: el
      // trigger handle_new_user() es la segunda barrera, no la única.
      await expectLater(
        AuthService.instance.register(
          name: 'Intruso',
          email: 'intruso@ride.app',
          phone: '0990000000',
          password: 'ClaveLarga123',
          role: UserRole.superadmin,
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('Sin sesión no se puede consultar la lista de usuarios', () async {
      await expectLater(
        AuthService.instance.visibleUsers(),
        throwsA(isA<AuthException>()),
      );
    });

    test('Sin sesión no se puede cambiar la contraseña inicial', () async {
      await expectLater(
        AuthService.instance.changeInitialPassword('ClaveDefinitiva123'),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
