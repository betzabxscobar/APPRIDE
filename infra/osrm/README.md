# Servidor de rutas propio (OSRM)

La app calcula las rutas con [OSRM](https://github.com/Project-OSRM/osrm-backend).
Mientras no se despliegue esto, apunta al **servidor público de demostración**,
que sirve para desarrollar pero **no para usuarios reales**: su política de uso
lo limita a pruebas, puede ir lento y puede cortar sin aviso. Lo mismo vale para
el de FOSSGIS (`routing.openstreetmap.de`).

Esta carpeta levanta el tuyo.

## Qué hace falta

- Una máquina Linux con **Docker** y **~4 GB de RAM**. La parte que más consume
  es `osrm-extract`; una vez construido el grafo, servirlo pide bastante menos.
- Unos **6 GB de disco** libres entre el mapa descargado y el grafo.
- Un **dominio** apuntando a esa máquina, con los puertos 80 y 443 abiertos.

> El dominio no es opcional. La app se sirve por HTTPS, y un navegador no deja
> que una página https llame a un http: lo bloquea por contenido mixto. Por eso
> el compose trae Caddy, que saca y renueva el certificado solo.

## Puesta en marcha

```bash
cd infra/osrm

cp .env.ejemplo .env
nano .env                 # poner el dominio real

./preparar.sh             # construye el grafo, tarda
docker compose up -d
```

`preparar.sh` descarga el mapa de Ecuador desde Geofabrik (~125 MB) y lo pasa
por los tres pasos de OSRM: `extract`, `partition` y `customize`. **Da poca
señal por pantalla y tarda**; en el propio proyecto avisan de que un mapa de
México de 550 MB tarda alrededor de media hora en el primer paso, así que
Ecuador, que es una quinta parte, debería ir bastante más rápido.

Para otro país se cambian las variables:

```bash
PAIS=colombia REGION=south-america ./preparar.sh
```

## Comprobar que funciona

```bash
curl "https://rutas.tudominio.com/route/v1/driving/-78.4880,-0.1760;-78.4750,-0.2050?overview=false"
```

Tiene que responder `{"code":"Ok"...}` con una distancia cercana a **5,9 km**,
que es lo que da ese trayecto de Quito.

## Apuntar la app

```bash
flutter build web --dart-define=OSRM_URL=https://rutas.tudominio.com
```

O en Android:

```bash
flutter build apk --dart-define=OSRM_URL=https://rutas.tudominio.com
```

Sin esa variable la app sigue usando el servidor de demostración. No se rompe,
pero no está lista para usuarios.

## Refrescar el mapa

Los datos de OpenStreetMap cambian: calles nuevas, sentidos que se invierten.
Conviene rehacer el grafo cada uno o dos meses.

```bash
cd infra/osrm
rm datos/ecuador-latest.osm.pbf   # fuerza la descarga del mapa nuevo
./preparar.sh
docker compose restart osrm
```

El servicio queda caído el rato que dure el reinicio. La app aguanta: si OSRM no
responde, dibuja la línea recta entre origen y destino en vez de fallar.

## Cosas que conviene saber

**OSRM no tiene autenticación.** Cualquiera que descubra el dominio puede
gastarte CPU. El `Caddyfile` deja pasar solo las rutas de la API y responde 404
al resto, pero eso no es un límite de uso: si el servicio se hace visible,
conviene meter un límite por IP o dejarlo detrás de Cloudflare.

**La versión de la imagen está fijada** (`v26.4.0`) a propósito. El grafo que
genera `osrm-extract` tiene que corresponder a la versión que luego lo sirve; con
`latest` una actualización silenciosa dejaría el servicio sin arrancar.

**El perfil es de coche** (`/opt/car.lua`). Para moto se cambia a
`motorcycle.lua` en `preparar.sh` y se vuelve a construir.

## Lo que no cubre esto

OSRM no conoce el tráfico: calcula con los límites de velocidad del mapa, no con
cómo está la avenida ahora mismo. Para tráfico real hay que alimentarlo con
datos de velocidad propios (`osrm-customize --segment-speed-file`), que salen de
los viajes que la app ya registra. Es el paso siguiente natural cuando haya
suficientes viajes.
