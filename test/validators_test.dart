import 'package:flutter_test/flutter_test.dart';
import 'package:ride/core/validators.dart';

/// Los dígitos verificadores de estos ejemplos se calcularon aparte, no con
/// este mismo código, para que la prueba sirva de algo.
void main() {
  group('cédula', () {
    test('acepta una cédula con el verificador correcto', () {
      expect(Validators.cedula('1701234567'), isNull);
      expect(Validators.cedula('170-123.456 7'), isNull, reason: 'ignora separadores');
    });

    test('rechaza el verificador cambiado', () {
      expect(Validators.cedula('1701234568'), isNotNull);
    });

    test('rechaza provincia inexistente y longitud incorrecta', () {
      expect(Validators.cedula('9901234567'), contains('provincia'));
      expect(Validators.cedula('17012345'), contains('diez'));
    });

    test('rechaza un RUC disfrazado de cédula', () {
      expect(Validators.cedula('1790123456'), contains('RUC'));
    });
  });

  group('RUC', () {
    test('acepta los tres tipos', () {
      expect(Validators.ruc('1701234567001'), isNull, reason: 'persona natural');
      expect(Validators.ruc('1760001200001'), isNull, reason: 'entidad pública');
      expect(Validators.ruc('1790123456001'), isNull, reason: 'sociedad privada');
    });

    test('rechaza el verificador cambiado en cada tipo', () {
      expect(Validators.ruc('1701234568001'), isNotNull);
      expect(Validators.ruc('1760001300001'), isNotNull);
      expect(Validators.ruc('1790123457001'), isNotNull);
    });

    test('rechaza tercer dígito sin tipo, establecimiento 000 y longitud', () {
      expect(Validators.ruc('1770123456001'), contains('tercer dígito'));
      expect(Validators.ruc('1701234567000'), contains('establecimiento'));
      expect(Validators.ruc('1701234567'), contains('trece'));
    });
  });

  group('placa', () {
    test('auto acepta tres y cuatro dígitos, con guion o sin él', () {
      expect(Validators.plateFor('PDC-1234', 'estandar'), isNull);
      expect(Validators.plateFor('pdc1234', 'confort'), isNull, reason: 'no distingue mayúsculas');
      expect(Validators.plateFor('PDC-123', 'xl'), isNull, reason: 'placas viejas');
    });

    test('moto acepta su formato y el auto lo rechaza', () {
      expect(Validators.plateFor('IA-123A', 'moto'), isNull);
      expect(Validators.plateFor('IA123', 'moto'), isNull, reason: 'sin letra final');
      expect(Validators.plateFor('PDC-1234', 'moto'), contains('moto'));
      expect(Validators.plateFor('IA-123A', 'estandar'), isNotNull);
    });

    test('sin tipo acepta cualquiera de los dos', () {
      expect(Validators.plate('PDC-1234'), isNull);
      expect(Validators.plate('IA-123A'), isNull);
      expect(Validators.plate('12345'), isNotNull);
    });
  });

  group('teléfono', () {
    test('acepta celular y convencional, escritos como sea', () {
      expect(Validators.phone('0991234567'), isNull);
      expect(Validators.phone('+593 99 123 4567'), isNull);
      expect(Validators.phone('593991234567'), isNull);
      expect(Validators.phone('02-2345678'), isNull, reason: 'convencional de Quito');
    });

    test('rechaza lo que antes pasaba de largo', () {
      expect(Validators.phone('12345678'), isNotNull, reason: 'no empieza en 0');
      expect(Validators.phone('099123456'), isNotNull, reason: 'un dígito de menos');
      expect(Validators.phone('09912345678'), isNotNull, reason: 'un dígito de más');
      expect(Validators.phone('0891234567'), isNotNull, reason: 'no hay operadora 08');
    });

    test('normaliza el +593 al cero nacional', () {
      expect(Validators.normalizarTelefono('+593 99 123 4567'), '0991234567');
      expect(Validators.normalizarTelefono('0991234567'), '0991234567');
    });
  });
}
