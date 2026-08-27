# Buscador de direcciones

`lib/services/geocoding_service.dart` busca direcciones con **Google Places** si
hay clave, y con **Photon** —geocodificador libre sobre OpenStreetMap— si no.

Sin clave la app funciona igual. Lo que cambia es la calidad de los datos.

## Por qué se añadió Google

En Quito el hueco de OSM es real y medible. Muestra de vías de cada ciudad,
mirando cuándo se editó cada una por última vez:

| Ciudad | Editado en 2026 | Últimos 2 años |
|---|---|---|
| Nueva York | 82 % | 88 % |
| Londres | 44 % | 78 % |
| Tokio | 34 % | 62 % |
| Madrid | 29 % | 51 % |
| São Paulo | 16 % | 39 % |
| Bogotá | 12 % | 28 % |
| Lagos | 11 % | 25 % |
| **Quito** | **6 %** | **9 %** |

Quito quedó última de las ocho, y por bastante. Que una calle se editara en 2022
no significa que esté mal —si no ha cambiado, sigue bien— pero un 9 % en dos
años, frente al 88 % de Nueva York, dice que hay mucho menos mantenimiento.

Cambiar a Mapbox, LocationIQ o Geoapify **no arregla esto**: todos derivan de
OSM y arrastran el mismo hueco. Solo Google, HERE y TomTom tienen datos propios.

## Lo que cuesta

Google no es gratis, por mucho que se optimice:

- Exige **cuenta de facturación con tarjeta**, aunque no se gaste.
- El tope gratuito son **10 000 llamadas al mes por servicio**.
- **No hay límite duro de gasto**, solo alertas de presupuesto. Con la clave
  dentro de un APK, un pico o una filtración es una factura real.

Por eso se usa **solo en el buscador**, no en el mapa. Un mapa dinámico gasta una
llamada cada vez que se abre una pantalla con mapa; el buscador gasta una por
búsqueda, que es muchísimo menos.

## Las dos optimizaciones que lo hacen barato

**1. Session tokens.** Google factura *por pulsación de teclado* si cada
petición va suelta. Agrupándolas con un mismo token, todas las sugerencias de
una búsqueda **más** la consulta de coordenadas del sitio elegido cuentan como
**una sola sesión**. La sesión se abre al empezar a escribir y se cierra en
`resolver()`.

**2. Coordenadas solo del elegido.** El autocompletado de Google no devuelve
coordenadas, solo un identificador. Se podrían pedir para los ocho resultados,
pero eso serían ocho llamadas por búsqueda. Se piden únicamente para el que la
persona toca, ya dentro de la sesión abierta.

A eso se suma lo que ya había: no buscar hasta los 3 caracteres, y esperar
350 ms a que dejen de escribir.

También se usa `X-Goog-FieldMask` para pedir solo los campos que se usan
(`placeId`, `structuredFormat` y `location`): el campo pedido decide en qué
tramo de precio cae la llamada.

## Poner la clave

1. En <https://console.cloud.google.com>, crea un proyecto y activa
   **Places API (New)** — no la antigua.
2. Crea una clave (empieza por `AIza`) y **restríngela**: por aplicación Android
   (nombre de paquete + huella SHA-1) o por dominio en web, y por API, dejando
   solo Places.
3. Compruébala antes de compilar:

   ```bash
   dart run tool/verificar_google.dart TU_CLAVE
   ```

   Hace las dos llamadas reales sobre una dirección de Quito y comprueba que
   comparten sesión. Si falta activar la API o la restricción bloquea, lo dice
   con el error de Google tal cual.

4. Compila con ella:

   ```bash
   flutter run --dart-define=GOOGLE_PLACES_KEY=TU_CLAVE
   ```

Sin la variable, o con un valor que no tenga forma de clave, la app usa Photon.
Eso es a propósito: mejor un buscador con datos flojos que uno que no encuentra
nada.

## Atribución

Google obliga a mostrar **«Powered by Google»** cuando se usan sus sugerencias
sin un mapa suyo, que es justo lo que hace esta pantalla. Sale al pie de la
lista de resultados. Con Photon, en el mismo sitio se acredita a OpenStreetMap.

## Lo que sigue en OSM

El **mapa** sigue siendo OpenStreetMap, y las **rutas** también (OSRM). Google
no se usa ahí:

- Sus condiciones dicen que los resultados deben mostrarse sobre un mapa de
  Google, lo que obligaría a migrar a `google_maps_flutter` y rehacer toda la
  capa de mapa.
- Un mapa dinámico consume cuota cada vez que se abre una pantalla.

Que una manzana esté algo desfasada en las teselas es cosmético. Que no
encuentre tu calle rompe el producto. Por eso el gasto se pone donde duele.
