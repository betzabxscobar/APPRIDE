/// Clave del buscador de direcciones de TomTom.
///
/// **Sin clave la app usa Photon**, el geocodificador libre sobre datos de
/// OpenStreetMap. Sigue funcionando; lo que se pierde es la calidad de los
/// datos donde OSM va flojo.
///
/// ## Por qué TomTom
///
/// En Quito el hueco de OSM es real y medible: de una muestra de vías del norte
/// de la ciudad, solo el 9 % se había editado en los últimos dos años, frente
/// al 88 % de Nueva York. Es la peor de las ocho ciudades que se midieron, y se
/// nota: barrios con el nombre antiguo, calles que la búsqueda no encuentra.
///
/// Cambiar a Mapbox, LocationIQ o Geoapify **no arregla nada**: los tres
/// derivan de OSM. Solo Google, HERE y TomTom tienen cartografía propia.
///
/// Google se descartó porque exige cuenta de facturación con tarjeta.
/// **TomTom no**: la clave se saca con un correo en
/// <https://developer.tomtom.com>, sin tarjeta, y su plan gratuito da 2 500
/// peticiones de búsqueda al día con uso comercial permitido.
///
/// ```sh
/// flutter run --dart-define=TOMTOM_KEY=la_clave
/// ```
///
/// Antes de compilar con ella conviene comprobar que mejora de verdad:
///
/// ```sh
/// dart run tool/comparar_buscador.dart la_clave "Alma Lojana"
/// ```
///
/// Enseña lo que devuelven Photon y TomTom para la misma búsqueda, uno al lado
/// del otro.
class BusquedaConfig {
  const BusquedaConfig._();

  static const String tomtomKey = String.fromEnvironment(
    'TOMTOM_KEY',
    defaultValue: '',
  );

  static bool get usaTomTom => claveValida(tomtomKey);

  /// Países donde opera Ride, en códigos ISO separados por comas.
  ///
  /// **No es un lugar por defecto**, es el alcance del servicio: lo que se le
  /// pasa a TomTom para que no ofrezca sitios de otros países. Sin esto,
  /// buscar «Terminal» desde Quito devolvía tres aeropuertos de España antes
  /// que nada de Ecuador, y «Madrigal» sacaba un pueblo de Colombia.
  ///
  /// Ojo con la diferencia: el **sesgo** por posición (`lat`/`lon`) sigue
  /// siendo eso, un sesgo, y ordena lo cercano primero sin descartar nada. La
  /// posición real de la persona no se toca ni se supone en ningún sitio.
  ///
  /// El día que Ride cruce la frontera, se añade el país aquí.
  static const String paisesServicio = 'EC';

  /// Las claves de TomTom son alfanuméricas y largas, sin prefijo distintivo.
  ///
  /// Se descartan URLs por lo mismo que en el resto de la app: es fácil pegar
  /// la dirección de un panel creyendo que es la clave, y con eso el buscador
  /// dejaría de encontrar nada. Mejor caer a Photon.
  static bool claveValida(String clave) {
    final k = clave.trim();
    return k.length >= 20 && !k.contains('/') && !k.contains('http');
  }
}
