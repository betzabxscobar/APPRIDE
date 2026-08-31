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

Por defecto la app usa el **servidor público de demostración**
(`router.project-osrm.org`), que no pide clave. Su política lo limita a
desarrollo: puede ir lento y puede cortar. Lo mismo vale para el de FOSSGIS
(`routing.openstreetmap.de`), que se probó y responde idéntico.

**Para producción hay que levantar el propio.** Está todo preparado en
`infra/osrm/`: Docker Compose con OSRM y Caddy —que saca el certificado HTTPS
solo— más un script que descarga el mapa de Ecuador y construye el grafo.

```bash
cd infra/osrm
cp .env.ejemplo .env && nano .env    # el dominio
./preparar.sh
docker compose up -d
```

Y se apunta la app ahí:

```bash
flutter build web --dart-define=OSRM_URL=https://rutas.tudominio.com
```

Tiene que ser **https**: una página servida por https no puede llamar a http, el
navegador lo bloquea por contenido mixto.

Detalles, requisitos de memoria y cómo refrescar el mapa, en
[`infra/osrm/README.md`](../infra/osrm/README.md).

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

## Teselas vectoriales: OpenFreeMap (2026-08-31)

Diego dijo que el mapa se veía desactualizado. Conviene separar dos cosas que
suenan igual:

- **Los datos NO estaban viejos.** `tile.openstreetmap.org` se refresca de forma
  continua.
- **El dibujo sí.** Son teselas *rasterizadas*: imágenes PNG de 256 px con el
  estilo clásico de OSM, de hace más de una década. En un teléfono moderno hay
  que ampliarlas, y se ven borrosas y anticuadas.

Lo que arregla eso son las **teselas vectoriales**: no traen el dibujo, traen
los datos, y los pinta el teléfono a la resolución de su pantalla.

### Proveedor: OpenFreeMap

**Sin clave, sin cuenta, sin tarjeta y sin cupo.** Es la única condición que
importa aquí: CARTO, Mapbox y Esri murieron todos en el mismo sitio, pidiendo
una clave (ver arriba).

- Estilo claro: `https://tiles.openfreemap.org/styles/liberty`
- Estilo oscuro: `https://tiles.openfreemap.org/styles/dark`

El oscuro es un estilo de verdad, no el truco de invertir los colores de una
imagen clara que hacía falta con OSM.

### Plugin: `flutter_map_vector_tiles`

`vector_map_tiles`, el más conocido, **no vale**: ni su versión estable ni sus
betas pasan de `flutter_map ^7`, y aquí hay 8.3.1. Usarlo obligaría a bajar de
versión flutter_map y a rehacer el mapa entero.

`flutter_map_vector_tiles` sí soporta `flutter_map ^8.2`. **Es un paquete
joven** (2 likes, publicador sin verificar), y por eso el mapa nunca depende de
que funcione: ver el respaldo, abajo.

### El respaldo importa más que el estilo

`RideMap` pinta **siempre** las teselas rasterizadas de OpenStreetMap primero, y
cambia a las vectoriales cuando el estilo termina de cargar. Si OpenFreeMap no
responde, si el paquete falla o si no hay red, el mapa se queda con el estilo de
siempre. **Nunca hay un hueco gris.** Un mapa feo es infinitamente mejor que un
mapa que no está.

### Lo que se verificó, y cómo

La lección de CARTO fue que un `200 OK` no prueba nada: sus teselas devolvían
`200 image/png` con «API KEY REQUIRED» dibujado dentro. Así que esta vez se
comprobó el contenido:

| Qué | Resultado |
|---|---|
| Los cinco estilos | JSON de MapLibre v8, sin `{key}` |
| TileJSON | compilación `20260823`, datos de OSM de 8 días antes |
| Una tesela real de Quito (z14) | 347 KB de MVT, con capas `water`, `building`, `transportation`, `place`, `landuse`, `boundary` |
| Fuentes (`glyphs`) | 76 KB de protobuf — sin esto no habría etiquetas |
| Iconos (`sprite`) | PNG de 512×263 **abierto y mirado**: iconos reales, ningún aviso de clave dentro |

**Lo que NO está verificado: cómo se ve.** En este entorno no se puede renderizar
Flutter, así que nadie ha visto todavía este mapa dibujado en una pantalla. Esa
comprobación es de Diego, con el APK en el teléfono.

### Atribución

Cambia con la capa: sobre el respaldo rasterizado solo se acredita a
OpenStreetMap; sobre el vectorial, `© OpenMapTiles © OpenStreetMap`, que es lo
que exigen las condiciones de OpenFreeMap.
