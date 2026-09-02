#!/usr/bin/env bash
#
# Construye el grafo de rutas de Ecuador. Se corre UNA vez antes del primer
# arranque, y despues cada vez que se quiera refrescar el mapa.
#
#   ./preparar.sh
#
# Tarda bastante y da poca senal por pantalla: es normal. En el README estan los
# tiempos y la memoria que hace falta.
set -euo pipefail

PAIS="${PAIS:-ecuador}"
REGION="${REGION:-south-america}"
IMAGEN="ghcr.io/project-osrm/osrm-backend:v26.4.0"
DATOS="$(cd "$(dirname "$0")" && pwd)/datos"
PBF="${PAIS}-latest.osm.pbf"

paso() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# En Git Bash (Windows), MSYS reescribe las rutas que le parecen unix antes de
# pasarselas a docker, y convierte `/data` en algo como
# `C:/Program Files/Git/data`. Con esto se queda quieto. En Linux y macOS estas
# variables no molestan.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

docker_osrm() {
  docker run --rm -t -v "${DATOS}:/data" "$IMAGEN" "$@"
}

command -v docker >/dev/null || {
  echo "Falta docker. Instalalo antes: https://docs.docker.com/engine/install/" >&2
  exit 1
}

mkdir -p "$DATOS"
cd "$DATOS"

paso "Descargando el mapa de ${PAIS}"
if [ -f "$PBF" ]; then
  echo "Ya estaba, se reutiliza. Borra $DATOS/$PBF para bajarlo de nuevo."
else
  curl -fL --progress-bar \
    -o "$PBF" \
    "https://download.geofabrik.de/${REGION}/${PBF}"
fi

# El grafo tiene que corresponder a la version del motor que luego lo sirve, asi
# que se rehace entero cada vez en lugar de mezclar restos de una anterior.
paso "Limpiando grafos anteriores"
find . -maxdepth 1 -name "${PAIS}-latest.osrm*" -delete

# `car.lua` es el perfil de coche que trae la imagen. Para moto o bici se
# cambia por motorcycle.lua o bicycle.lua.
paso "1/3 osrm-extract (el paso largo)"
docker_osrm osrm-extract -p /opt/car.lua "/data/${PBF}"

paso "2/3 osrm-partition"
docker_osrm osrm-partition "/data/${PAIS}-latest.osrm"

paso "3/3 osrm-customize"
docker_osrm osrm-customize "/data/${PAIS}-latest.osrm"

paso "Listo"
du -sh "$DATOS" | awk '{print "El grafo ocupa " $1}'
echo
echo "En tu maquina:   docker compose -f docker-compose.local.yml up -d"
echo "                 flutter run --dart-define=OSRM_URL=http://localhost:5000"
echo
echo "En un servidor:  docker compose up -d"
