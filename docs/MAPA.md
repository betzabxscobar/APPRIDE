# El mapa de Ride

**Sin claves, sin cuentas y sin cuotas.** La app funciona recién clonada, sin
configurar nada.

| Qué | Quién | Clave |
|---|---|---|
| Teselas del mapa | [OpenStreetMap](https://www.openstreetmap.org) | ninguna |
| Rutas por calles | [OSRM](https://github.com/Project-OSRM/osrm-backend) | ninguna |

En modo oscuro las teselas claras de OSM se invierten con el filtro de
`flutter_map`, porque OSM no publica un estilo oscuro.

## Zoom

OpenStreetMap sirve teselas **hasta z19**; de z20 en adelante responde `400`.

Eso lo cubre `maxNativeZoom: 19`: a partir de ahí `flutter_map` reutiliza la
tesela de z19 y la escala, así que se puede seguir acercando y el mapa sigue
ahí, solo que menos nítido.

> **No poner `maxZoom` en el `TileLayer`.** Ese parámetro es hasta dónde se
> *dibuja* la capa, no hasta dónde llega la fuente, y su valor por defecto es
> infinito precisamente para que siempre haya teselas. Fijarlo en 19 dejaba el
> mapa **en negro** en cuanto te acercabas más. Hay un test que lo vigila:
> «Zoom del mapa».

El gesto de zoom está acotado en `MapOptions` entre z3 y z21: más allá la tesela
escalada ya no aporta nada, y más acá el mundo se repite en pantalla.

## Rutas

`lib/services/routing_service.dart` le pide a OSRM el recorrido real por calles
entre dos puntos. Antes el mapa unía origen y destino con una **línea recta**,
que atravesaba manzanas y ríos.

`RideMap` lo usa solo: cuando `ruta` trae dos puntos, dibuja la recta de
entrada —para que siempre haya algo— y la sustituye por el trazado real en
cuanto llega. Si OSRM no responde, se queda la recta y no pasa nada más.

Solo se recalcula cuando cambian el origen o el destino. En seguimiento la ruta
se cachea por origen+destino: Realtime reconstruye esa pantalla cada minuto al
reportar el chofer, y el recorrido no cambia por eso.

> **Estaba escrito pero no conectado.** Hasta el 2026-08-27 `RoutingService` no
> lo llamaba nadie: las dos pantallas con mapa dibujaban `[origen, destino]`,
> una recta de dos puntos. Eso era «la ruta se ve muy mal».

### Cuál de las rutas se elige

OSRM ordena por **tiempo**, no por distancia, y a veces la segunda tarda lo
mismo y es más corta —medido en Quito: 9,29 km y 10,39 km, las dos en 22,6 min—.
Por eso se piden alternativas y decide `elegirMejor`: de las que no tardan más
de un 10 % sobre la más rápida, se queda con la más corta. Tiene pruebas.

### La distancia y el tiempo NO fijan el precio

La tarifa la calcula `cotizar_viaje` en Postgres y ahí se queda: el cliente se
puede manipular, así que no puede decir cuánto cuesta un viaje.

Pero conviene saber que **no coinciden**. Postgres usa la distancia en línea
recta por un factor de `1.35`, no el camino real. Medido en Quito sobre el mismo
par de puntos:

| | km |
|---|---|
| Línea recta | 3,53 |
| Lo que cobra (× 1.35) | 4,77 |
| Ruta real (OSRM) | 5,92 |

La tarifa se queda un ~19 % corta en ese trayecto. Subir el factor o pasar a
cobrar por distancia real es una decisión de negocio, no técnica.

### El servidor de OSRM

Ahora mismo se usa el **servidor público de demostración**
(`router.project-osrm.org`), que no pide clave. Su política de uso lo limita a
desarrollo y pruebas: **no está pensado para producción** y puede ir lento o
cortar si se abusa.

Para producción hay que levantar el propio con
[osrm-backend](https://github.com/Project-OSRM/osrm-backend) — es justo para eso.
Cuando llegue el momento solo hay que cambiar `_servidor` en
`routing_service.dart`; el resto del código no se entera.

## Por qué no un mapa «más bonito»

El estilo de OSM está pensado para leerse solo, así que compite un poco con los
marcadores. Se probaron las alternativas y **todas exigen clave, cuenta, o las
dos**:

| Vía | Qué pasó |
|---|---|
| **CARTO raster** sin clave | Responde `200 image/png`, pero con «API KEY REQUIRED» estampado *dentro* de la imagen. Con teselas hay que mirar el PNG, no el código HTTP. |
| **CARTO raster** con clave | Funciona y se ve muy bien. La clave es gratis y no pide cuenta (<https://carto.com/basemaps/apikey>, llega por correo), con un tope de uso razonable de 5 M teselas/mes. Ojo: **no** es lo mismo que un *API Access Token* del workspace de CARTO, ni que la URL de su servidor MCP. |
| **Mapbox** | `light-v11` / `dark-v11` se ven muy bien y un token malo falla limpio (`401`, no marca de agua). Pero exige crear cuenta y su capa gratuita son 50 000 cargas/mes. |
| **Esri Gray Canvas** | Limpio y sin clave, pero su capa de etiquetas está vacía de z13 en adelante. Un mapa sin nombres de calle no sirve para elegir dónde te recogen. |
| **CARTO vectorial** (`vector_map_tiles`) | Es lo que usa [mapcn](https://www.mapcn.dev/) por debajo, y los datos son correctos —`style.json` con 93 capas, teselas `.mvt` sin clave, CORS abierto— pero el mapa salía en negro y no se pudo depurar. |
| **`maplibre_gl`** | El motor oficial de MapLibre. Obligaba a reescribir `RideMap` entero: marcadores, rutas y controlador cambian de API. |

Si algún día se quiere un mapa **sin ningún límite y sin clave**, la opción real
es [OpenFreeMap](https://openfreemap.org/): sin registro, sin tope y con uso
comercial permitido. El pero es que solo sirve teselas **vectoriales**, que es
el camino que no quedó funcionando.

### mapcn

[mapcn](https://www.mapcn.dev/) es **React** — `npx shadcn@latest add @mapcn/map`
copia componentes JSX. Hay ports de Svelte, Vue, React Native y Angular; **de
Flutter no hay**, así que en esta app no se puede usar.

En **WEB-RIDE**, que sí es React, entra tal cual con ese comando.

## Dónde se centra el mapa y dónde busca las direcciones

Lo decide `lib/core/map_defaults.dart`, a partir de la última posición leída
(`LocationService.ultimaConocida`). Si todavía no hay ninguna, se muestra una
vista de país a zoom 6 — un encuadre general, que no afirma nada sobre dónde
estás.

**Nunca volver a poner una ciudad escrita a mano ahí.** Antes las cuatro
pantallas con mapa tenían `LatLng(-2.1709, -79.9224)` —Guayaquil— como relleno,
y eso rompía la búsqueda de direcciones para todo el que no estuviera en
Guayaquil. Buscando «La Carolina» (un parque de Quito):

| Sesgo | Resultados |
|---|---|
| Ninguno | Jaén (España), Coronel Pringles (Argentina), Quito |
| Guayaquil | Pimocha, Pimocha, Quevedo |
| La posición real (Quito) | Quito, Quito, Quito |

El sesgo se le pasa a Photon como `lat`/`lon`, y no es opcional: sin él, los
nombres de calle repetidos devuelven el de otro país.

## Atribución

La licencia ODbL obliga a acreditar OpenStreetMap allí donde se muestren sus
datos, así que el crédito del mapa no se puede quitar. En las pantallas con hoja
arrastrable sube con la hoja (`margenCredito`) para que nunca quede detrás.
