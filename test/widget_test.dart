import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride/main.dart';
import 'package:ride/models/app_user.dart';
import 'package:ride/models/fleet.dart';
import 'package:ride/services/geocoding_service.dart';
import 'package:ride/models/trip.dart';
import 'package:ride/models/user_role.dart';
import 'package:ride/models/vehicle.dart';
import 'package:ride/screens/auth/auth_screen.dart';
import 'package:ride/services/auth_service.dart';
import 'package:ride/widgets/auth_shell.dart';
import 'package:ride/widgets/panel_switcher.dart';

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

  group('Estados del viaje', () {
    test('Los nueve estados coinciden con el enum de Postgres', () {
      // Deben ser exactamente los valores de public.enum_estado_viaje.
      expect(TripStatus.values.map((e) => e.id).toList(), [
        'SOLICITADO',
        'BUSCANDO_CONDUCTOR',
        'ACEPTADO',
        'CONDUCTOR_EN_CAMINO',
        'CONDUCTOR_EN_ORIGEN',
        'EN_CURSO',
        'FINALIZADO',
        'CANCELADO',
        'SIN_CONDUCTOR',
      ]);
    });

    test('Solo finalizado, cancelado y sin chofer cierran el viaje', () {
      final finales =
          TripStatus.values.where((e) => e.esFinal).map((e) => e.id).toSet();
      expect(finales, {'FINALIZADO', 'CANCELADO', 'SIN_CONDUCTOR'});
    });

    test('Un viaje en curso ya no se puede cancelar', () {
      // La persona va a bordo: cancelar ahí no tiene sentido, y la funcion
      // cancelar_viaje() lo rechaza igual del lado del servidor.
      expect(TripStatus.enCurso.sePuedeCancelar, isFalse);
      expect(TripStatus.finalizado.sePuedeCancelar, isFalse);
      expect(TripStatus.solicitado.sePuedeCancelar, isTrue);
      expect(TripStatus.conductorEnOrigen.sePuedeCancelar, isTrue);
    });

    test('Solo hay chofer que mostrar desde que acepta y hasta que cierra', () {
      expect(TripStatus.buscandoConductor.tieneConductor, isFalse);
      expect(TripStatus.aceptado.tieneConductor, isTrue);
      expect(TripStatus.enCurso.tieneConductor, isTrue);
      expect(TripStatus.finalizado.tieneConductor, isFalse);
    });

    test('Un estado desconocido no rompe la app', () {
      expect(TripStatus.fromId('ALGO_RARO'), TripStatus.solicitado);
    });

    test('El progreso avanza con el recorrido', () {
      expect(TripStatus.solicitado.progreso,
          lessThan(TripStatus.aceptado.progreso));
      expect(TripStatus.aceptado.progreso,
          lessThan(TripStatus.enCurso.progreso));
      expect(TripStatus.finalizado.progreso, 1);
    });
  });

  group('Geocodificación', () {
    test('El texto completo une nombre y contexto', () {
      const p = GeoPlace(
        nombre: 'Calle de Serrano 21',
        direccion: 'Madrid, España',
        lat: 40.42, lng: -3.68,
      );
      expect(p.completo, 'Calle de Serrano 21, Madrid, España');
    });

    test('Sin contexto no queda una coma suelta', () {
      const p = GeoPlace(
        nombre: 'Tu ubicación actual', direccion: '', lat: 0, lng: 0,
      );
      expect(p.completo, 'Tu ubicación actual');
    });

    test('Textos muy cortos no salen a la red', () async {
      // Photon ignora consultas de una o dos letras y solo gastarían batería.
      expect(await GeocodingService.instance.buscar('a'), isEmpty);
      expect(await GeocodingService.instance.buscar('ab'), isEmpty);
      expect(await GeocodingService.instance.buscar('   '), isEmpty);
    });
  });

  group('Flota y documentos', () {
    test('Los tres tipos coinciden con el CHECK de la base', () {
      expect(DocumentType.values.map((d) => d.id).toList(),
          ['licencia', 'SOAT', 'matricula']);
    });

    test('Los estados coinciden con el CHECK de la base', () {
      expect(DocumentStatus.values.map((d) => d.id).toList(),
          ['pendiente', 'aprobado', 'rechazado']);
    });

    test('Un tipo o estado desconocido no rompe la app', () {
      expect(DocumentType.fromId('pasaporte'), DocumentType.licencia);
      expect(DocumentStatus.fromId('raro'), DocumentStatus.pendiente);
    });

    test('El resumen del vehículo se arma para mostrarlo al pasajero', () {
      const v = FleetVehicle(
        id: 'v-1', placa: 'ABC-1234', marca: 'Kia', modelo: 'Rio',
        anio: 2022, activo: true, color: 'Blanco',
      );
      expect(v.resumen, 'Kia Rio · 2022');
    });
  });

  group('Métodos de pago', () {
    test('El efectivo se describe sin exponer nada', () {
      const m = PaymentMethod(id: 'm-1', tipo: 'efectivo', predeterminado: true);
      expect(m.esEfectivo, isTrue);
      expect(m.label, 'Efectivo');
      expect(m.descripcion, 'Pagas al llegar');
    });

    test('De la tarjeta solo se muestran los últimos caracteres del token', () {
      // Nunca es un número de tarjeta: la base rechaza cualquier cosa con
      // forma de PAN. Aun así, del token tampoco se enseña todo.
      const m = PaymentMethod(
        id: 'm-2', tipo: 'tarjeta', predeterminado: false,
        detalle: 'tok_abc123XYZ9',
      );
      expect(m.descripcion, '···· XYZ9');
      expect(m.descripcion.contains('tok_abc'), isFalse);
    });

    test('Un token muy corto no se recorta a la fuerza', () {
      const m = PaymentMethod(
        id: 'm-3', tipo: 'tarjeta', predeterminado: false, detalle: 'ab',
      );
      expect(m.descripcion, 'Tarjeta guardada');
    });
  });

  group('Notificaciones', () {
    AppNotification aviso(Duration antiguedad) => AppNotification(
          id: 'n-1', titulo: 'Chofer asignado', mensaje: 'Va en camino',
          leida: false, fecha: DateTime.now().subtract(antiguedad),
        );

    test('El texto relativo se adapta a la antigüedad', () {
      expect(aviso(const Duration(seconds: 20)).cuando, 'ahora');
      expect(aviso(const Duration(minutes: 5)).cuando, 'hace 5 min');
      expect(aviso(const Duration(hours: 3)).cuando, 'hace 3 h');
      expect(aviso(const Duration(days: 1, hours: 1)).cuando, 'ayer');
      expect(aviso(const Duration(days: 4)).cuando, 'hace 4 días');
    });
  });

  group('Acceso entre paneles', () {
    test('El superadmin llega a los cuatro paneles', () {
      expect(UserRole.superadmin.viewsAllowed(), [
        UserRole.superadmin,
        UserRole.admin,
        UserRole.passenger,
        UserRole.driver,
      ]);
    });

    test('El admin NO puede abrir la vista de superadmin', () {
      final vistas = UserRole.admin.viewsAllowed();
      expect(vistas.contains(UserRole.superadmin), isFalse);
      // Sí conserva su panel y las dos vistas operativas.
      expect(vistas, [UserRole.admin, UserRole.passenger, UserRole.driver]);
    });

    test('Ningún rol no administrativo alcanza un panel administrativo', () {
      for (final rol in [UserRole.passenger, UserRole.driver]) {
        final vistas = rol.viewsAllowed(hasVehicle: true);
        expect(vistas.any((v) => v.isAdministrative), isFalse, reason: rol.id);
      }
    });

    test('Todos pueden volver a su propio panel', () {
      for (final rol in UserRole.values) {
        expect(rol.viewsAllowed(hasVehicle: true), contains(rol),
            reason: rol.id);
      }
    });

    test('Un pasajero sin vehículo no puede abrir la vista de chofer', () {
      expect(UserRole.passenger.viewsAllowed(), [UserRole.passenger]);
      expect(UserRole.passenger.viewsAllowed(hasVehicle: true),
          [UserRole.passenger, UserRole.driver]);
    });
  });

  group('Etiquetas de panel', () {
    test('Cada vista se nombra como pantalla, no como rol', () {
      // Importa la distinción: un superadmin que abre la vista de pasajero no
      // pasa a ser pasajero, solo mira esa pantalla.
      expect(panelLabel(UserRole.superadmin), 'Panel de superadmin');
      expect(panelLabel(UserRole.admin), 'Panel de administración');
      expect(panelLabel(UserRole.passenger), 'Vista de usuario');
      expect(panelLabel(UserRole.driver), 'Vista de chofer');
    });
  });

  group('AuthService', () {
    test('Sin sesión no hay vistas disponibles', () {
      expect(AuthService.instance.availableViews, isEmpty);
    });

    test('Sin sesión, cambiar de vista no hace nada', () {
      // No debe lanzar: simplemente no hay nada que cambiar.
      AuthService.instance.switchView(UserRole.admin);
      expect(AuthService.instance.isViewingOtherPanel, isFalse);
    });

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
