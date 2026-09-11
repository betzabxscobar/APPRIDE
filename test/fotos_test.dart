import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ride/core/fotos.dart';

/// Un JPEG liso del tamaño pedido, con la orientación EXIF que se le diga.
Uint8List jpeg(int ancho, int alto, {int? orientacion}) {
  final foto = img.Image(width: ancho, height: alto);
  img.fill(foto, color: img.ColorRgb8(40, 90, 160));
  if (orientacion != null) foto.exif.imageIfd.orientation = orientacion;
  return img.encodeJpg(foto, quality: 90);
}

/// Mete a mano, detrás del inicio del JPEG, un bloque EXIF con una marca que se
/// puede buscar. Hace de las coordenadas: si la marca sobrevive, el GPS también
/// sobreviviría.
Uint8List conBloqueExif(Uint8List jpg) {
  final carga = latin1.encode(
    'Exif\x00\x00MM\x00*\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00RIDE-GPS-TEST',
  );
  final largo = carga.length + 2;
  return Uint8List.fromList([
    ...jpg.sublist(0, 2),
    0xFF, 0xE1, largo >> 8, largo & 0xFF,
    ...carga,
    ...jpg.sublist(2),
  ]);
}

bool contiene(Uint8List bytes, String texto) =>
    latin1.decode(bytes).contains(texto);

img.Image leer(Uint8List bytes) => img.decodeJpg(bytes)!;

Matcher fotoInvalida(String mensaje) => throwsA(
      isA<FotoInvalida>().having((e) => e.message, 'message', mensaje),
    );

void main() {
  group('Fotos antes de subir', () {
    test('quita el bloque EXIF entero, con lo que llevara dentro', () {
      final entrada = conBloqueExif(jpeg(1200, 900));
      expect(contiene(entrada, 'Exif'), isTrue,
          reason: 'la prueba no vale si la entrada no lo lleva');
      expect(contiene(entrada, 'RIDE-GPS-TEST'), isTrue);

      final salida = prepararFotoAhora(entrada, LimitesFoto.documento);
      expect(contiene(salida, 'Exif'), isFalse);
      expect(contiene(salida, 'RIDE-GPS-TEST'), isFalse);
    });

    test('una foto en vertical sale derecha, y sin EXIF', () {
      // 6 = girar 90° a la derecha: lo que manda un móvil en vertical.
      // Se lee el EXIF crudo: `decodeJpg` ya endereza la foto al leerla y
      // borra la etiqueta, así que por ahí no se vería.
      final entrada = jpeg(1200, 900, orientacion: 6);
      expect(img.decodeJpgExif(entrada)?.imageIfd.orientation, 6,
          reason: 'la prueba no vale si la entrada no la lleva');

      final salida = prepararFotoAhora(entrada, LimitesFoto.documento);
      final foto = leer(salida);
      expect([foto.width, foto.height], [900, 1200]);
      expect(img.decodeJpgExif(salida)?.imageIfd.hasOrientation ?? false,
          isFalse);
      expect(contiene(salida, 'Exif'), isFalse);
    });

    test('sale siempre JPEG, aunque entre un PNG', () {
      final png = img.encodePng(img.Image(width: 700, height: 700));
      final salida = prepararFotoAhora(png, LimitesFoto.documento);
      expect(salida.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('lo transparente de un PNG sale blanco, no negro', () {
      final logo = img.Image(width: 100, height: 100, numChannels: 4);
      img.fillRect(logo,
          x1: 30, y1: 30, x2: 70, y2: 70, color: img.ColorRgba8(220, 0, 0, 255));

      final foto = leer(prepararFotoAhora(img.encodePng(logo), LimitesFoto.avatar));
      final esquina = foto.getPixel(5, 5);
      final centro = foto.getPixel(50, 50);
      expect([esquina.r, esquina.g, esquina.b], everyElement(greaterThan(245)));
      expect(centro.r, greaterThan(200));
      expect(centro.g, lessThan(40));
    });

    test('un documento se queda en 1600 de ancho, como en la web', () {
      final foto = leer(prepararFotoAhora(jpeg(2000, 1500), LimitesFoto.documento));
      expect([foto.width, foto.height], [1600, 1200]);
    });

    test('el avatar cabe en 800×800 por los dos lados', () {
      final foto = leer(prepararFotoAhora(jpeg(1000, 2000), LimitesFoto.avatar));
      expect([foto.width, foto.height], [400, 800]);
    });

    test('nunca amplía una foto pequeña', () {
      final foto = leer(prepararFotoAhora(jpeg(500, 400), LimitesFoto.avatar));
      expect([foto.width, foto.height], [500, 400]);
    });

    test('el comprobante solo se limita a lo ancho: una captura alta sigue legible', () {
      final foto =
          leer(prepararFotoAhora(jpeg(1080, 2400), LimitesFoto.comprobante));
      expect([foto.width, foto.height], [1080, 2400]);
    });

    test('mide lo que queda: una panorámica acaba por debajo de 600 y se rechaza', () {
      expect(
        () => prepararFotoAhora(jpeg(3200, 800), LimitesFoto.documento),
        fotoInvalida(
          'Esa foto es demasiado pequeña (1600×400). Tiene que medir al menos '
          '600 píxeles de lado para que se lea.',
        ),
      );
    });

    test('lo que no es una foto lo dice así, no con un error de la librería', () {
      expect(
        () => prepararFotoAhora(
            Uint8List.fromList(utf8.encode('hola')), LimitesFoto.documento),
        fotoInvalida('Ese archivo no es una foto que podamos leer.'),
      );
    });

    test('en otro isolate da lo mismo, y el error llega con su tipo', () async {
      final salida = await prepararFoto(jpeg(2000, 1500), LimitesFoto.documento);
      expect(leer(salida).width, 1600);

      await expectLater(
        prepararFoto(jpeg(3200, 800), LimitesFoto.documento),
        throwsA(isA<FotoInvalida>()),
      );
    });

    test('mismos números que la web (src/lib/image-upload.ts)', () {
      String n(LimitesFoto l) =>
          '${l.maxAncho}/${l.maxAlto}/${l.calidad}/${l.ladoMinimo}';
      expect(n(LimitesFoto.avatar), '800/800/82/null');
      expect(n(LimitesFoto.documento), '1600/null/80/600');
      expect(n(LimitesFoto.comprobante), '1600/null/85/null');
    });
  });
}
