import 'package:flutter_test/flutter_test.dart';
import 'package:ride/models/user_role.dart';

/// Lo que rodea a «Quiero ser chofer».
///
/// El cambio de rol lo hace `quiero_ser_chofer()` en Postgres y ahí es donde
/// están sus guardas —no puede aprobarse solo, no puede subirse a
/// administrativo, no puede cambiar con un viaje en marcha—. Lo que sí vive en
/// la app, y por tanto se prueba aquí, es qué pantallas puede abrir cada rol
/// una vez hecho el cambio.
void main() {
  group('a dónde llega cada rol después del cambio', () {
    test('un pasajero solo ve su propia pantalla', () {
      expect(UserRole.passenger.viewsAllowed(), [UserRole.passenger],
          reason: 'para conducir hay que pasarse a chofer, no asomarse');
    });

    test('al pasar a chofer gana la pantalla de chofer y conserva la de usuario',
        () {
      final vistas = UserRole.driver.viewsAllowed();
      expect(vistas, contains(UserRole.driver));
      expect(vistas, contains(UserRole.passenger),
          reason: 'sigue pudiendo pedir viajes como pasajero');
    });

    test('un chofer recién convertido, sin vehículo, llega a su pantalla', () {
      // Es la regresión que dejaba a alguien atrapado: se exigía vehículo para
      // abrir la vista de chofer, y el vehículo se registra justamente ahí.
      expect(UserRole.driver.viewsAllowed(), contains(UserRole.driver));
    });

    test('pasar a chofer no acerca a ningún panel administrativo', () {
      expect(
        UserRole.driver.viewsAllowed().any((v) => v.isAdministrative),
        isFalse,
      );
    });

    test('todos pueden volver a su propio panel', () {
      for (final rol in UserRole.values) {
        expect(rol.viewsAllowed(), contains(rol), reason: rol.id);
      }
    });
  });

  group('los dos roles del cambio', () {
    test('pasajero y chofer son los únicos que se eligen en la app', () {
      expect(UserRole.selectable, [UserRole.passenger, UserRole.driver],
          reason: 'las cuentas administrativas no se crean desde aquí');
    });

    test('ninguno de los dos es administrativo', () {
      expect(UserRole.passenger.isAdministrative, isFalse);
      expect(UserRole.driver.isAdministrative, isFalse);
    });

    test('se distinguen por sus banderas', () {
      expect(UserRole.passenger.isPassenger, isTrue);
      expect(UserRole.passenger.isDriver, isFalse);
      expect(UserRole.driver.isDriver, isTrue);
      expect(UserRole.driver.isPassenger, isFalse);
    });

    test('el id que viaja a la base es el que espera Postgres', () {
      // `quiero_ser_chofer()` deja el rol en 'driver'; si estos textos no
      // coinciden, el perfil vuelve con un rol que la app no reconoce.
      expect(UserRole.passenger.id, 'passenger');
      expect(UserRole.driver.id, 'driver');
      expect(UserRole.fromId('driver'), UserRole.driver);
      expect(UserRole.fromId('passenger'), UserRole.passenger);
    });

    test('un rol desconocido cae en pasajero, no revienta', () {
      expect(UserRole.fromId('chofer'), UserRole.passenger,
          reason: 'el valor de la base es el ingles, no el español');
      expect(UserRole.fromId(''), UserRole.passenger);
    });
  });
}
