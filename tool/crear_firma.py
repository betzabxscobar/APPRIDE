"""Crea la clave de firma de publicacion de Ride y `android/key.properties`.

    python tool/crear_firma.py

La contrasena la escribes tu aqui, sin que se vea, y no sale de este equipo: se
le pasa a keytool por una variable de entorno del proceso, no por la linea de
comandos, asi que tampoco queda en el historial ni en la lista de procesos.

Una sola vez. Despues `flutter build apk --release` y `flutter build appbundle`
firman solos. Y **guarda copia** de `android/ride-publicacion.jks` y de la
contrasena en dos sitios distintos: si se pierden, Play Store no deja publicar
ninguna actualizacion de la app nunca mas.
"""

import getpass
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
ALMACEN = RAIZ / 'android' / 'ride-publicacion.jks'
PROPIEDADES = RAIZ / 'android' / 'key.properties'
ALIAS = 'ride'
TITULAR = 'CN=Ride, OU=Ride, O=Ride Viajes, L=Quito, ST=Pichincha, C=EC'


def buscar_keytool():
    candidatos = [shutil.which('keytool')]
    if os.environ.get('JAVA_HOME'):
        candidatos.append(str(Path(os.environ['JAVA_HOME']) / 'bin' / 'keytool.exe'))
    candidatos += sorted(glob.glob(r'C:\Program Files\Java\*\bin\keytool.exe'), reverse=True)
    candidatos.append(r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe')
    return next((c for c in candidatos if c and Path(c).is_file()), None)


def main():
    # Nunca se pisa una clave existente: la de hoy es la unica que valdra para
    # actualizar la app publicada.
    for existente in (ALMACEN, PROPIEDADES):
        if existente.exists():
            sys.exit(f'Ya existe {existente.relative_to(RAIZ)}. No lo sobrescribo.')

    keytool = buscar_keytool()
    if not keytool:
        sys.exit('No encuentro keytool. Instala un JDK o Android Studio.')

    clave = getpass.getpass('Contrasena para la clave de firma (minimo 8): ')
    if len(clave) < 8:
        sys.exit('Demasiado corta.')
    if getpass.getpass('Repitela: ') != clave:
        sys.exit('No coinciden.')

    # PKCS12 usa una sola contrasena para el almacen y la clave.
    entorno = dict(os.environ, RIDE_FIRMA=clave)
    subprocess.run(
        [keytool, '-genkeypair', '-v',
         '-keystore', str(ALMACEN), '-storetype', 'PKCS12',
         '-alias', ALIAS, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
         '-dname', TITULAR,
         '-storepass:env', 'RIDE_FIRMA', '-keypass:env', 'RIDE_FIRMA'],
        env=entorno, check=True,
    )

    # `storeFile` es relativo a android/app, que es donde lo lee Gradle.
    PROPIEDADES.write_text(
        f'storePassword={clave}\nkeyPassword={clave}\nkeyAlias={ALIAS}\n'
        'storeFile=../ride-publicacion.jks\n',
        encoding='utf-8',
    )
    print('\nListo: android/ride-publicacion.jks y android/key.properties (los dos ignorados por git).')
    print('Guarda copia de los dos, y de la contrasena, en dos sitios distintos.')


if __name__ == '__main__':
    main()
