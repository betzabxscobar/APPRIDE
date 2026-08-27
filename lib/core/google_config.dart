/// Clave de Google Places, si se tiene una.
///
/// **Sin clave la app usa Photon**, el geocodificador libre sobre datos de
/// OpenStreetMap. Sigue funcionando; lo que se pierde es la calidad de los
/// datos donde OSM va flojo.
///
/// Se puso porque en Quito ese hueco es real y medible: de una muestra de vías
/// del norte de la ciudad, solo el 9 % se había editado en los últimos dos
/// años, frente al 88 % de Nueva York o el 78 % de Londres. Fue la ciudad peor
/// mantenida de las ocho que se midieron.
///
/// Ojo con lo que implica activarla:
///
/// * Google exige **cuenta de facturación con tarjeta**, aunque no se gaste.
/// * El tope gratuito son 10 000 llamadas al mes por servicio.
/// * **No hay límite duro de gasto**, solo alertas de presupuesto.
///
/// Por eso el buscador usa *session tokens*: sin ellos Google factura cada
/// pulsación de teclado, y con ellos toda la búsqueda más la consulta de
/// coordenadas cuentan como una sola sesión. Ver [GeocodingService].
///
/// ```sh
/// flutter run --dart-define=GOOGLE_PLACES_KEY=la_clave
/// ```
///
/// Para comprobar que la clave sirve antes de compilar:
///
/// ```sh
/// dart run tool/verificar_google.dart la_clave
/// ```
class GoogleConfig {
  const GoogleConfig._();

  static const String placesKey = String.fromEnvironment(
    'GOOGLE_PLACES_KEY',
    defaultValue: '',
  );

  /// `true` cuando hay una clave con pinta de serlo.
  ///
  /// Las claves de Google empiezan por `AIza`. Se comprueba para que una URL o
  /// un identificador pegado por error caiga a Photon en vez de provocar un
  /// buscador que no encuentra nada.
  static bool get usaGoogle => claveValida(placesKey);

  static bool claveValida(String clave) {
    final k = clave.trim();
    return k.startsWith('AIza') && k.length >= 30;
  }
}
