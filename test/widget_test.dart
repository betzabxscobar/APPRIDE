import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride/main.dart';
import 'package:ride/models/user_role.dart';
import 'package:ride/services/auth_service.dart';

void main() {
  tearDown(() async {
    await AuthService.instance.signOut();
  });

  testWidgets('El botón Continuar se habilita al elegir un rol', (tester) async {
    await tester.pumpWidget(const RideApp());

    final continuar = find.widgetWithText(FilledButton, 'Continuar');
    expect(tester.widget<FilledButton>(continuar).onPressed, isNull);

    await tester.tap(find.text('Viajo'));
    await tester.pump();

    expect(tester.widget<FilledButton>(continuar).onPressed, isNotNull);
  });

  testWidgets('Login de pasajero lleva al home de pasajero', (tester) async {
    await tester.pumpWidget(const RideApp());

    await tester.tap(find.text('Viajo'));
    await tester.pump();

    final continuar = find.widgetWithText(FilledButton, 'Continuar');
    await tester.ensureVisible(continuar);
    await tester.pump();
    await tester.tap(continuar);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'pasajero@ride.app',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Ride1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.textContaining('¡Hola, Andrea!'), findsOneWidget);
  });

  testWidgets('El registro de conductor pide los datos del vehículo',
      (tester) async {
    await tester.pumpWidget(const RideApp());

    await tester.tap(find.text('Conduzco'));
    await tester.pump();

    final continuar = find.widgetWithText(FilledButton, 'Continuar');
    await tester.ensureVisible(continuar);
    await tester.pump();
    await tester.tap(continuar);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Regístrate'));
    await tester.pumpAndSettle();

    // El formulario es un ListView perezoso: hay que desplazarse hasta la
    // sección del vehículo para que se construya.
    await tester.dragUntilVisible(
      find.text('Tu vehículo'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu vehículo'), findsOneWidget);
    expect(find.text('Placa'), findsOneWidget);
  });

  testWidgets('El home de conductor muestra las oportunidades',
      (tester) async {
    // Sin await: el retardo simulado del servicio avanza con el reloj falso
    // del test, que solo corre durante los pump().
    final pendingSignIn = AuthService.instance.signIn(
      email: 'conductor@ride.app',
      password: 'Ride1234',
      expectedRole: UserRole.driver,
    );

    await tester.pumpWidget(const RideApp());
    await tester.pumpAndSettle();
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

  test('Login rechaza el rol equivocado', () async {
    await expectLater(
      AuthService.instance.signIn(
        email: 'pasajero@ride.app',
        password: 'Ride1234',
        expectedRole: UserRole.driver,
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

  test('Una cuenta administrativa entra sin importar el rol elegido',
      () async {
    final admin = await AuthService.instance.signIn(
      email: 'alexyanez1119@gmail.com',
      password: AuthService.temporaryAdminPassword,
      expectedRole: UserRole.passenger,
    );

    expect(admin.role, UserRole.admin);
    expect(admin.mustChangePassword, isTrue);

    // Mientras no cambie la contraseña temporal no puede ver el listado.
    expect(() => AuthService.instance.visibleUsers(),
        throwsA(isA<AuthException>()));

    final updated =
        await AuthService.instance.changeInitialPassword('RideSegura2026');
    expect(updated.mustChangePassword, isFalse);

    // Un admin no ve a los superadmin; un superadmin sí.
    final visibles = AuthService.instance.visibleUsers();
    expect(visibles.any((user) => user.role.isSuperadmin), isFalse);
    expect(visibles.any((user) => user.email == 'alexyanez1119@gmail.com'),
        isTrue);
  });

  test('El primer acceso exige una contraseña de 10 caracteres', () async {
    await AuthService.instance.signIn(
      email: 'betzabxscobar@gmail.com',
      password: AuthService.temporaryAdminPassword,
    );

    await expectLater(
      AuthService.instance.changeInitialPassword('Corta123'),
      throwsA(isA<AuthException>()),
    );
  });
}
