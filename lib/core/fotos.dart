import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Cómo tiene que quedar una foto antes de subirla a Storage.
///
/// Los mismos números que `src/lib/image-upload.ts` en la web. Si se cambia
/// uno, se cambia el otro: la prueba «mismos números que la web» los fija.
@immutable
class LimitesFoto {
  const LimitesFoto({
    required this.maxAncho,
    this.maxAlto,
    required this.calidad,
    this.ladoMinimo,
  });

  /// Ancho máximo. Se reduce manteniendo la proporción; nunca se amplía.
  final int maxAncho;

  /// Alto máximo, si lo hay. Solo el avatar lo tiene.
  final int? maxAlto;

  /// Calidad JPEG, de 0 a 100.
  final int calidad;

  /// Lado mínimo que tiene que quedar para que se pueda leer.
  final int? ladoMinimo;

  /// Se ve a 60 px: 800 sobra.
  static const avatar = LimitesFoto(maxAncho: 800, maxAlto: 800, calidad: 82);

  /// Un documento se lee, no se imprime. Y tiene suelo: el bucket limita el
  /// tamaño por arriba, pero eso no distingue una foto legible de una de 40×30
  /// píxeles, y por debajo de 600 no se lee un número de placa ni el de una
  /// póliza. Esa se rechazaría igual, solo que tres días después.
  static const documento =
      LimitesFoto(maxAncho: 1600, calidad: 80, ladoMinimo: 600);

  /// Solo a lo ancho: un comprobante suele ser una captura de pantalla alta y
  /// estrecha, y limitarla a lo alto dejaría el texto ilegible.
  static const comprobante = LimitesFoto(maxAncho: 1600, calidad: 85);
}

/// La foto no se puede subir; [message] dice por qué, en palabras del usuario.
class FotoInvalida implements Exception {
  const FotoInvalida(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Devuelve la foto en JPEG, derecha, reducida y sin metadatos.
///
/// Lo de los metadatos es lo importante. `image_picker` en Android, al
/// reducir, copia a la foto nueva las etiquetas EXIF de la original, las del
/// GPS incluidas (`ExifDataCopier.java`): una foto de perfil tomada en casa se
/// subía a un bucket público con las coordenadas de esa casa dentro.
///
/// Corre en otro isolate: decodificar y volver a codificar una foto de 1600 px
/// en Dart lleva su rato, y en el hilo principal congelaría la pantalla.
Future<Uint8List> prepararFoto(Uint8List bytes, LimitesFoto limites) =>
    compute(_prepararEnIsolate, (bytes, limites));

Uint8List _prepararEnIsolate((Uint8List, LimitesFoto) datos) =>
    prepararFotoAhora(datos.$1, datos.$2);

/// Lo mismo que [prepararFoto], en el hilo que llama.
@visibleForTesting
Uint8List prepararFotoAhora(Uint8List bytes, LimitesFoto limites) {
  img.Image? original;
  try {
    original = img.decodeImage(bytes);
  } catch (_) {
    // Un JPEG cortado a medias puede hacer fallar al decodificador por dentro,
    // y ese error no le dice nada a nadie.
    original = null;
  }
  if (original == null) {
    throw const FotoInvalida('Ese archivo no es una foto que podamos leer.');
  }

  // image_picker no gira los píxeles: deja la orientación en el EXIF. Si se
  // quitara el EXIF sin más, las fotos en vertical saldrían tumbadas. Con un
  // JPEG ya lo hace el decodificador de `image` al leerlo, y esto no hace
  // nada; queda para los PNG y WebP que traigan orientación.
  final derecha = img.bakeOrientation(original);

  final escala = [
    1.0,
    limites.maxAncho / derecha.width,
    if (limites.maxAlto != null) limites.maxAlto! / derecha.height,
  ].reduce(math.min);
  final ancho = (derecha.width * escala).round();
  final alto = (derecha.height * escala).round();

  // Se mide lo que va a quedar, no lo que llegó, igual que en la web: una
  // panorámica de 4000×1000 pasa del suelo, pero a 1600 de ancho se queda en
  // 400 de alto y no se lee.
  final minimo = limites.ladoMinimo;
  if (minimo != null && (ancho < minimo || alto < minimo)) {
    throw FotoInvalida(
      'Esa foto es demasiado pequeña ($ancho×$alto). Tiene que medir al '
      'menos $minimo píxeles de lado para que se lea.',
    );
  }

  var limpia = escala < 1
      ? img.copyResize(
          derecha,
          width: ancho,
          height: alto,
          interpolation: img.Interpolation.average,
        )
      : derecha;

  // JPEG no tiene transparencia: lo transparente de un PNG saldría negro.
  if (limpia.hasAlpha) {
    final fondo = img.Image(width: limpia.width, height: limpia.height);
    img.fill(fondo, color: img.ColorRgb8(255, 255, 255));
    limpia = img.compositeImage(fondo, limpia);
  }

  // Ni el decodificador ni `bakeOrientation` quitan el EXIF: los dos enderezan
  // la foto y borran la orientación, pero copian todo lo demás, GPS incluido.
  // Se vacía a mano justo antes de codificar, que es lo único que no depende
  // de qué arrastre cada paso de antes.
  limpia.exif = img.ExifData();
  return img.encodeJpg(limpia, quality: limites.calidad);
}
