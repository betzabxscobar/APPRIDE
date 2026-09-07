import 'package:flutter_test/flutter_test.dart';
import 'package:ride/models/fleet.dart';

/// Un documento tal como llega de `documentos_conductor`.
DriverDocument doc({
  required String tipo,
  required String estado,
  String? caducaEl,
}) =>
    DriverDocument.fromMap({
      'id': 'd1',
      'tipo_documento': tipo,
      'estado': estado,
      'url_archivo': 'x',
      'fecha_subida': '2026-09-01T10:00:00Z',
      'caduca_el': caducaEl,
    });

void main() {
  group('un papel aprobado sin fecha de caducidad', () {
    // Este es el caso exacto que tumbaba el perfil del chofer: en la base hay
    // matrículas y SPPAT aprobados con `caduca_el` en null. La pantalla los
    // daba por vencidos y acto seguido pedía la fecha que no existe.
    final matricula = doc(tipo: 'matricula', estado: 'aprobado');

    test('no se da por vencido: no se sabe', () {
      expect(matricula.vencido, isFalse,
          reason: 'sin fecha no hay nada que haya vencido');
    });

    test('se marca como sin fecha, que es lo que de verdad pasa', () {
      expect(matricula.sinFecha, isTrue);
    });

    test('tampoco cuenta como vigente para dejar trabajar', () {
      expect(matricula.vigente, isFalse,
          reason: 'no consta que sirva, así que no habilita');
    });

    test('no avisa de que caduca pronto', () {
      expect(matricula.porCaducar, isFalse);
    });
  });

  group('con fecha, cada estado en su sitio', () {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final enUnaSemana = DateTime.now().add(const Duration(days: 7));
    final enDosAnios = DateTime.now().add(const Duration(days: 730));

    test('caducado ayer sí está vencido', () {
      final d = doc(
          tipo: 'SPPAT', estado: 'aprobado', caducaEl: ayer.toIso8601String());
      expect(d.vencido, isTrue);
      expect(d.sinFecha, isFalse);
      expect(d.vigente, isFalse);
    });

    test('caduca en una semana: vigente, pero avisando', () {
      final d = doc(
          tipo: 'SPPAT',
          estado: 'aprobado',
          caducaEl: enUnaSemana.toIso8601String());
      expect(d.vencido, isFalse);
      expect(d.porCaducar, isTrue);
      expect(d.vigente, isTrue);
    });

    test('caduca en dos años: tranquilo', () {
      final d = doc(
          tipo: 'SPPAT',
          estado: 'aprobado',
          caducaEl: enDosAnios.toIso8601String());
      expect(d.vencido, isFalse);
      expect(d.porCaducar, isFalse);
      expect(d.vigente, isTrue);
    });
  });

  group('estados que no son aprobado', () {
    test('uno pendiente no está vencido ni le falta fecha', () {
      final d = doc(tipo: 'matricula', estado: 'pendiente');
      expect(d.vencido, isFalse);
      expect(d.sinFecha, isFalse,
          reason: 'todavía no lo revisan, la fecha no toca aún');
      expect(d.vigente, isFalse);
    });

    test('uno rechazado tampoco', () {
      final d = doc(tipo: 'matricula', estado: 'rechazado');
      expect(d.vencido, isFalse);
      expect(d.sinFecha, isFalse);
    });
  });

  test('un papel que no caduca nunca está vencido ni sin fecha', () {
    final cedula = doc(tipo: 'cedula', estado: 'aprobado');
    expect(cedula.vencido, isFalse);
    expect(cedula.sinFecha, isFalse);
    expect(cedula.vigente, isTrue, reason: 'una cédula aprobada sirve y ya');
  });
}
