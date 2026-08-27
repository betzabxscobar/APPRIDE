# Buscador de direcciones

`lib/services/geocoding_service.dart` busca con **Photon**
(<https://photon.komoot.io>), un geocodificador libre sobre datos de
OpenStreetMap. Sin clave, sin cuenta y con cobertura mundial.

## El hueco de Quito, medido

Los datos de OSM en Quito están claramente menos mantenidos que en otras
ciudades. Muestra de vías por ciudad, mirando cuándo se editó cada una por
última vez:

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

Quito quedó última de las ocho, y por bastante.

Un matiz importante: que una calle se editara en 2022 **no significa que esté
mal**. Si no ha cambiado, sigue siendo correcta. Pero un 9 % en dos años, frente
al 88 % de Nueva York, indica mucho menos mantenimiento, y eso se nota en
direcciones nuevas o poco comunes.

## Lo que NO arregla esto

**Cambiar a Mapbox, LocationIQ o Geoapify no sirve de nada.** Los tres derivan
de OpenStreetMap y arrastran exactamente el mismo hueco. Solo **Google, HERE y
TomTom** tienen datos propios.

## Por qué no se usa Google

Se llegó a implementar y **se retiró**: Google Cloud no deja activar las APIs de
Maps sin **cuenta de facturación con tarjeta**, aunque no se llegue a gastar.

Aparte de la tarjeta, lo que habría implicado:

- Tope gratuito de 10 000 llamadas al mes por servicio.
- **Sin límite duro de gasto**, solo alertas de presupuesto. Con la clave dentro
  de un APK, un pico o una filtración es una factura real.
- Sus condiciones obligan a mostrar los resultados sobre un mapa de Google, así
  que solo se podía usar en el buscador —no en el mapa— y con la atribución
  «Powered by Google» a la vista.

Si algún día hay tarjeta y se retoma, lo que hacía barata la integración era:
**session tokens** (sin ellos Google cobra por cada pulsación de teclado; con
ellos toda la búsqueda más la consulta de coordenadas cuentan como una sola
sesión) y pedir las coordenadas **solo del lugar elegido**, no de los ocho
resultados. Está en el historial de git, en el commit «Busca direcciones con
Google Places cuando hay clave».

## Qué se puede hacer sin tarjeta

Lo que ya amortigua el hueco, y funciona hoy:

- **Elegir el punto en el mapa.** El botón *Mapa* del buscador permite tocar
  dónde es exactamente, y la app hace geocodificación inversa para ponerle
  nombre. Es la salida cuando la búsqueda no encuentra la dirección.
- **Historial y lugares guardados** (`PlacesService`). Una dirección que OSM no
  conoce se busca a mano una vez y después ya sale en la lista.
- **Sesgo por posición.** Los resultados se ordenan alrededor de donde estás.
  Ver `docs/MAPA.md`.

Y hay una opción que no cuesta dinero: **editar OpenStreetMap**. Es abierto, y
lo que se corrige aparece en las teselas en minutos y en las rutas al
reconstruir el grafo. No es realista mantener una ciudad entera a mano, pero sí
las zonas donde más molesta.

## Límite de uso de Photon

El servidor lo dona Komoot y pide no abusar. Para desarrollo y demos va bien.
Con usuarios reales conviene auto-hospedarlo. El cambio afecta solo a
`GeocodingService`.

## Atribución

La licencia de OpenStreetMap obliga a acreditar los datos allí donde se
muestren. El crédito sale al pie de la lista de resultados.
