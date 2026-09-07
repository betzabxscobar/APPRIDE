import 'package:flutter_test/flutter_test.dart';
import 'package:ride/models/trip.dart';

/// Fila mínima de `viajes_detalle`, con lo que se le quiera añadir encima.
Map<String, dynamic> fila([Map<String, dynamic> extra = const {}]) => {
      'id': 'v1',
      'estado': 'FINALIZADO',
      'pasajero_id': 'p1',
      'tarifa_estimada': 4.50,
      'fecha_solicitud': '2026-09-06T10:00:00Z',
      'tarifa_nombre': 'Estándar',
      'pasajero_nombre': 'Diego',
      'origen_texto': 'La Carolina',
      'destino_texto': 'La Floresta',
      ...extra,
    };

void main() {
  group('estado del cobro', () {
    test('un viaje recién cerrado no cuenta como pagado', () {
      final viaje = Trip.fromMap(fila({'pago_estado': 'pendiente'}));
      expect(viaje.pagoPendiente, isTrue);
      expect(viaje.pagoConfirmado, isFalse,
          reason: 'el efectivo ya no se da por cobrado al finalizar');
    });

    test('solo cuenta como pagado cuando el cobro está completado', () {
      final viaje = Trip.fromMap(fila({
        'pago_estado': 'completado',
        'monto_cobrado': 4.50,
      }));
      expect(viaje.pagoConfirmado, isTrue);
      expect(viaje.pagoPendiente, isFalse);
      expect(viaje.montoCobrado, 4.50);
    });

    test('sin cobro todavía, ninguna de las dos', () {
      final viaje = Trip.fromMap(fila());
      expect(viaje.pagoConfirmado, isFalse);
      expect(viaje.pagoPendiente, isFalse);
      expect(viaje.montoCobrado, 0, reason: 'no cobrado es cero, no null');
    });

    test('un cobro fallido tampoco es un cobro', () {
      final viaje = Trip.fromMap(fila({'pago_estado': 'fallido'}));
      expect(viaje.pagoConfirmado, isFalse);
      expect(viaje.pagoPendiente, isFalse);
    });
  });

  group('llegada al destino', () {
    test('llegada comprobada', () {
      final viaje = Trip.fromMap(fila({
        'llegada_verificada': true,
        'desvio_detectado': false,
        'distancia_recorrida_km': 5.2,
      }));
      expect(viaje.llegadaVerificada, isTrue);
      expect(viaje.desvioDetectado, isFalse);
    });

    test('sin rastro GPS queda en null, que no es lo mismo que estar bien', () {
      final viaje = Trip.fromMap(fila({'llegada_verificada': null}));
      expect(viaje.llegadaVerificada, isNull);
      expect(viaje.llegadaVerificada ?? false, isFalse,
          reason: 'null nunca se debe leer como llegada comprobada');
    });

    test('un rodeo queda marcado', () {
      final viaje = Trip.fromMap(fila({
        'llegada_verificada': true,
        'desvio_detectado': true,
        'distancia_recorrida_km': 18.4,
      }));
      expect(viaje.desvioDetectado, isTrue);
      expect(viaje.distanciaRecorridaKm, 18.4);
    });
  });

  group('cancelación', () {
    test('queda quién canceló y por qué', () {
      final viaje = Trip.fromMap(fila({
        'estado': 'CANCELADO',
        'cancelado_por': 'p1',
        'motivo_cancelacion': 'Cancelado por el pasajero',
      }));
      expect(viaje.canceladoPor, 'p1');
      expect(viaje.motivoCancelacion, 'Cancelado por el pasajero');
    });

    test('EN_CURSO no se puede cancelar', () {
      expect(TripStatus.enCurso.sePuedeCancelar, isFalse,
          reason: 'con la persona a bordo el viaje solo termina finalizando');
      expect(TripStatus.conductorEnOrigen.sePuedeCancelar, isTrue);
    });
  });

  group('multa por cancelación tardía', () {
    test('solo cuenta como tardía con el chofer ya en el punto', () {
      expect(TripStatus.conductorEnOrigen.cancelarTieneMulta, isTrue);
      expect(TripStatus.conductorEnCamino.cancelarTieneMulta, isFalse,
          reason: 'todavía viene en camino, cancelar sale gratis');
      expect(TripStatus.aceptado.cancelarTieneMulta, isFalse);
      expect(TripStatus.buscandoConductor.cancelarTieneMulta, isFalse);
      expect(TripStatus.solicitado.cancelarTieneMulta, isFalse);
    });

    test('un viaje cancelado tarde trae la multa', () {
      final viaje = Trip.fromMap(fila({
        'estado': 'CANCELADO',
        'cancelado_por': 'p1',
        'multa': 1.00,
        'pago_estado': 'pendiente',
      }));
      expect(viaje.multa, 1.00);
      expect(viaje.tieneMulta, isTrue);
      expect(viaje.pagoPendiente, isTrue,
          reason: 'la multa queda por cobrar, no cobrada');
    });

    test('sin multa la cifra es cero, no null', () {
      final viaje = Trip.fromMap(fila({'estado': 'CANCELADO'}));
      expect(viaje.multa, 0);
      expect(viaje.tieneMulta, isFalse);
    });
  });

  test('los campos nuevos sobreviven al guardado local', () {
    final viaje = Trip.fromMap(fila({
      'pago_estado': 'pendiente',
      'llegada_verificada': true,
      'desvio_detectado': false,
      'distancia_recorrida_km': 5.2,
      'cancelado_por': null,
      'motivo_cancelacion': null,
      'multa': 1.00,
    }));
    final vuelta = Trip.fromMap(viaje.toMap());

    expect(vuelta.pagoEstado, 'pendiente');
    expect(vuelta.llegadaVerificada, isTrue);
    expect(vuelta.desvioDetectado, isFalse);
    expect(vuelta.distanciaRecorridaKm, 5.2);
    expect(vuelta.multa, 1.00);
  });
}
