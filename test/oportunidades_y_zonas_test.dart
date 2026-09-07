import 'package:flutter_test/flutter_test.dart';
import 'package:ride/models/fleet.dart';
import 'package:ride/models/trip.dart';

Map<String, dynamic> fila([Map<String, dynamic> extra = const {}]) => {
      'id': 'v1',
      'estado': 'BUSCANDO_CONDUCTOR',
      'pasajero_id': 'p1',
      'tarifa_estimada': 9.88,
      'fecha_solicitud': '2026-09-07T10:00:00Z',
      'tarifa_nombre': 'Estándar',
      'pasajero_nombre': 'Diego',
      'origen_texto': 'La Carolina',
      'destino_texto': 'Cumbayá',
      ...extra,
    };

void main() {
  group('lo que necesita una oportunidad', () {
    test('la ganancia viene del servidor, no se calcula aquí', () {
      final viaje = Trip.fromMap(fila({
        'tarifa_estimada': 9.88,
        'gana_conductor': 8.40,
      }));
      expect(viaje.ganaConductor, 8.40);
      expect(viaje.ganaConductor, isNot(viaje.tarifaEstimada),
          reason: 'lo que gana no es lo que paga el pasajero');
    });

    test('distancia y minutos llegan calculados', () {
      final viaje = Trip.fromMap(fila({
        'distancia_km': 6.2,
        'minutos_estimados': 14,
        'zona_origen': 'quito_norte',
      }));
      expect(viaje.distanciaKm, 6.2);
      expect(viaje.minutosEstimados, 14);
      expect(viaje.zonaOrigen, 'quito_norte');
    });

    test('un viaje viejo sin estos datos no revienta la tarjeta', () {
      final viaje = Trip.fromMap(fila());
      expect(viaje.ganaConductor, isNull);
      expect(viaje.distanciaKm, isNull);
      expect(viaje.minutosEstimados, isNull);
      expect(viaje.zonaOrigen, isNull,
          reason: 'la tarjeta esconde lo que no sabe en vez de poner un cero');
    });

    test('un origen fuera de todas las zonas deja la zona en null', () {
      expect(Trip.fromMap(fila({'zona_origen': null})).zonaOrigen, isNull);
    });

    test('los campos nuevos sobreviven al guardado local', () {
      final viaje = Trip.fromMap(fila({
        'gana_conductor': 8.40,
        'distancia_km': 6.2,
        'minutos_estimados': 14,
        'zona_origen': 'quito_norte',
      }));
      final vuelta = Trip.fromMap(viaje.toMap());
      expect(vuelta.ganaConductor, 8.40);
      expect(vuelta.distanciaKm, 6.2);
      expect(vuelta.minutosEstimados, 14);
      expect(vuelta.zonaOrigen, 'quito_norte');
    });
  });

  group('la fila que devuelve solicitudes_abiertas', () {
    // La función de base no manda el nombre ni el teléfono del pasajero: para
    // decidir si acepta no le hacen falta, y solo deben llegarle al aceptar.
    // El modelo tiene que armarse igual con esa fila más corta.
    final deLaFuncion = <String, dynamic>{
      'id': 'v9',
      'estado': 'BUSCANDO_CONDUCTOR',
      'pasajero_id': 'p9',
      'tarifa_estimada': 4.50,
      'tarifa_nombre': 'Tarifa Estandar',
      'fecha_solicitud': '2026-09-07T14:00:00Z',
      'origen_lat': -0.1807,
      'origen_lng': -78.4678,
      'origen_texto': 'La Carolina',
      'destino_lat': -0.1750,
      'destino_lng': -78.4800,
      'destino_texto': '6 de Diciembre',
      'categoria': 'estandar',
      'categoria_nombre': 'Estándar',
      'gana_conductor': 3.83,
      'distancia_km': 1.6,
      'minutos_estimados': 4,
      'zona_origen': 'quito_norte',
    };

    test('se arma sin los datos del pasajero', () {
      final viaje = Trip.fromMap(deLaFuncion);
      expect(viaje.id, 'v9');
      expect(viaje.status, TripStatus.buscandoConductor);
      expect(viaje.ganaConductor, 3.83);
      expect(viaje.zonaOrigen, 'quito_norte');
    });

    test('el nombre y el teléfono del pasajero no vienen', () {
      final viaje = Trip.fromMap(deLaFuncion);
      expect(viaje.pasajeroTelefono, isNull,
          reason: 'no se le entrega hasta que acepta');
      expect(viaje.pasajeroNombre, 'Pasajero',
          reason: 'un relleno, no un dato real del pasajero');
    });

    test('trae origen y destino para poder pintar la tarjeta', () {
      final viaje = Trip.fromMap(deLaFuncion);
      expect(viaje.origenTexto, 'La Carolina');
      expect(viaje.destinoTexto, '6 de Diciembre');
      expect(viaje.origenLat, -0.1807);
      expect(viaje.destinoLng, -78.4800);
    });
  });

  group('zona de trabajo', () {
    test('se arma con lo que devuelve mis_zonas', () {
      final zona = WorkZone.fromMap({
        'id': 'quito_norte',
        'nombre': 'Quito Norte',
        'elegida': true,
      });
      expect(zona.id, 'quito_norte');
      expect(zona.nombre, 'Quito Norte');
      expect(zona.elegida, isTrue);
    });

    test('una zona sin marcar llega en false, no en null', () {
      final zona = WorkZone.fromMap({
        'id': 'los_chillos',
        'nombre': 'Valle de los Chillos',
        'elegida': null,
      });
      expect(zona.elegida, isFalse);
    });

    test('copyWith solo cambia si está elegida', () {
      const zona = WorkZone(id: 'z', nombre: 'Z', elegida: false);
      final marcada = zona.copyWith(elegida: true);
      expect(marcada.elegida, isTrue);
      expect(marcada.id, 'z');
      expect(marcada.nombre, 'Z');
      expect(zona.elegida, isFalse, reason: 'la original no se toca');
    });
  });
}
