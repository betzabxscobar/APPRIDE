import 'package:flutter_test/flutter_test.dart';
import 'package:ride/core/validators.dart';
import 'package:ride/models/fleet.dart';

void main() {
  group('número de cuenta', () {
    test('acepta los largos que usan los bancos de aquí', () {
      expect(Validators.numeroDeCuenta('2100123456'), isNull, reason: '10 dígitos');
      expect(Validators.numeroDeCuenta('12345678901'), isNull, reason: '11 dígitos');
      expect(Validators.numeroDeCuenta('2100-123456'), isNull,
          reason: 'los separadores se ignoran');
    });

    test('rechaza letras, vacío y largos imposibles', () {
      expect(Validators.numeroDeCuenta('21001234ab'), isNotNull);
      expect(Validators.numeroDeCuenta(''), isNotNull);
      expect(Validators.numeroDeCuenta('12345'), isNotNull, reason: 'muy corto');
      expect(Validators.numeroDeCuenta('1' * 21), isNotNull, reason: 'muy largo');
    });
  });

  group('banco del catálogo', () {
    test('arma la ruta del asset a partir de la clave', () {
      const banco = Bank(id: 'pichincha', nombre: 'Banco Pichincha', logo: 'banco_pichincha');
      expect(banco.assetLogo, 'assets/images/bancos/banco_pichincha.png');
    });

    test('los cuatro bancos del catálogo tienen su logo', () {
      const bancos = [
        Bank(id: 'pichincha', nombre: 'Banco Pichincha', logo: 'banco_pichincha'),
        Bank(id: 'guayaquil', nombre: 'Banco Guayaquil', logo: 'banco_guayaquil'),
        Bank(id: 'internacional', nombre: 'Banco Internacional', logo: 'banco_internacional'),
        Bank(id: 'produbanco', nombre: 'Produbanco', logo: 'produbanco'),
      ];
      for (final b in bancos) {
        expect(b.assetLogo, 'assets/images/bancos/${b.logo}.png',
            reason: '${b.nombre} tiene que apuntar a un asset empaquetado');
      }
    });

    test('un banco sin logo no tiene ruta y cae a las iniciales', () {
      // El respaldo sigue existiendo para el próximo banco que se añada al
      // catálogo antes de conseguir su imagen.
      const banco = Bank(id: 'otro', nombre: 'Banco Bolivariano', color: '#0033A0');
      expect(banco.assetLogo, isNull,
          reason: 'sin esto la app pediría un asset que no existe');
      expect(banco.iniciales, 'BB');
    });

    test('las iniciales salen de las dos primeras palabras', () {
      expect(const Bank(id: 'p', nombre: 'Produbanco').iniciales, 'PR',
          reason: 'una sola palabra da sus dos primeras letras');
      expect(const Bank(id: 'i', nombre: 'Banco Internacional').iniciales, 'BI');
    });

    test('el color de marca se lee del hex', () {
      const banco = Bank(id: 'x', nombre: 'X', color: '#00713C');
      expect(banco.colorMarca?.toARGB32(), 0xFF00713C);
    });

    test('un color roto no revienta, se queda en null', () {
      expect(const Bank(id: 'x', nombre: 'X', color: 'verde').colorMarca, isNull);
      expect(const Bank(id: 'x', nombre: 'X').colorMarca, isNull);
    });
  });

  group('cuenta del chofer', () {
    Map<String, dynamic> fila([Map<String, dynamic> extra = const {}]) => {
          'id': 'c1',
          'banco': 'pichincha',
          'banco_nombre': 'Banco Pichincha',
          'banco_logo': 'banco_pichincha',
          'banco_color': '#FFDD00',
          'tipo': 'ahorros',
          'numero': '2100123456',
          'titular': 'Diego Zurita',
          'predeterminada': true,
          ...extra,
        };

    test('se arma con lo que devuelve cuentas_del_chofer', () {
      final cuenta = BankAccount.fromMap(fila({'cedula_titular': '1701234567'}));
      expect(cuenta.numero, '2100123456');
      expect(cuenta.tipoLabel, 'Cuenta de ahorros');
      expect(cuenta.cedulaTitular, '1701234567');
      expect(cuenta.predeterminada, isTrue);
    });

    test('la corriente se nombra distinto', () {
      expect(BankAccount.fromMap(fila({'tipo': 'corriente'})).tipoLabel,
          'Cuenta corriente');
    });

    test('sin cédula del titular la cuenta sigue siendo válida', () {
      expect(BankAccount.fromMap(fila()).cedulaTitular, isNull);
    });

    test('lleva dentro el banco para poder pintar el logo', () {
      final banco = BankAccount.fromMap(fila()).bancoComoCatalogo;
      expect(banco.id, 'pichincha');
      expect(banco.assetLogo, 'assets/images/bancos/banco_pichincha.png');
    });

    test('un banco sin logo llega con null y no rompe la tarjeta', () {
      final cuenta = BankAccount.fromMap(fila({
        'banco': 'otro',
        'banco_nombre': 'Banco Bolivariano',
        'banco_logo': null,
        'banco_color': '#0033A0',
      }));
      expect(cuenta.bancoComoCatalogo.assetLogo, isNull);
      expect(cuenta.bancoComoCatalogo.iniciales, 'BB');
    });
  });

  group('método de pago', () {
    PaymentMethod metodo(String tipo) => PaymentMethod.fromMap({
          'id': 'm1',
          'tipo': tipo,
          'predeterminado': true,
          'detalle_tokenizado': null,
        });

    test('la transferencia es un método más, sin token', () {
      final m = metodo('transferencia');
      expect(m.esTransferencia, isTrue);
      expect(m.esEfectivo, isFalse);
      expect(m.esDeuna, isFalse);
      expect(m.label, 'Transferencia');
      expect(m.detalle, isNull,
          reason: 'la cuenta es del chofer, no se guarda nada del pasajero');
    });

    test('no se confunde con los otros métodos', () {
      expect(metodo('efectivo').esTransferencia, isFalse);
      expect(metodo('deuna').esTransferencia, isFalse);
      expect(metodo('tarjeta').esTransferencia, isFalse);
    });
  });
}
