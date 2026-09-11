# Publicar Ride

Qué hay que tener resuelto antes de subir la app a Play Store, y cómo se hace
cada cosa. Lo que ya está hecho no se repite aquí; esto es lo que falta y lo que
solo puede decidir una persona.

## Lo que ya está resuelto

| Pieza | Estado |
|---|---|
| Identificador de la app | `com.rideviajes.ride` — **confirmar antes de publicar**, ver abajo |
| Icono | El logo de Ride, adaptativo y clásico ([CUOTA.md](CUOTA.md) no, ver README) |
| Ofuscación y recorte (`minify`, `shrinkResources`) | activados en release |
| Copia de seguridad de la sesión | excluida de Google Drive y del traspaso entre teléfonos |
| Vuelta de PayPal (`ride://suscripcion/...`) | registrada en el manifiesto |
| Permisos | los cuatro que se usan, ninguno de más |
| Escritura anónima en la base | revocada en las 25 tablas |
| Escritura directa con sesión | cerrada en `viajes`, `ubicaciones`, `pagos`, `mensajes` y demás tablas que solo tocan las funciones; del perfil solo se editan nombre, teléfono y foto |
| Quién ve qué perfil | cada uno el suyo y el de la otra persona de sus viajes; administración, todos |
| Cuota con el mes de cortesía | el cobro de PayPal cierra la cortesía y encadena el mes; cancelar respeta lo pagado |

Lo de las tres últimas filas salió de la segunda auditoría del 2026-09-11 y lo
vigila `infra/sql/pruebas/permisos.sql`. **Falta la prueba con teléfonos**: un
viaje completo con una cuenta de chofer que **no** sea superadmin (ver §8).

## Lo que falta, y es una decisión

### 1. El identificador de la app

Estaba en `com.example.ride`, que Play Store rechaza por ser el de ejemplo de
Flutter. Se cambió a **`com.rideviajes.ride`**.

> **Esto no se puede cambiar después de publicar.** Una app con otro
> `applicationId` es, para Play Store, una app distinta: sin actualizaciones,
> sin reseñas, sin instalaciones. Si el equipo prefiere otro nombre, este es el
> momento — se cambia en [`android/app/build.gradle.kts`](../android/app/build.gradle.kts).

Efecto inmediato: la próxima APK **se instala como app nueva** al lado de la que
haya en el teléfono, en vez de actualizarla. Conviene desinstalar la vieja.

### 2. La clave de firma

**La forma corta:** `python tool/crear_firma.py`. Pide la contraseña sin
mostrarla, crea `android/ride-publicacion.jks` y `android/key.properties`, y se
niega a pisar una clave que ya exista. Lo de abajo es lo mismo, a mano.

Hasta ahora las APK van firmadas con la clave de depuración. Sirve para repartir
entre el equipo; Play Store la rechaza. Y una firmada en depuración no deja
actualizar encima de una firmada de verdad: hay que desinstalar.

Genera el almacén —una sola vez, y **guárdalo bien**: si se pierde, no hay forma
de volver a publicar una actualización de esa app, nunca—:

```bash
keytool -genkey -v -keystore ride-publicacion.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ride
```

Te pedirá una contraseña y algunos datos. Después, crea `android/key.properties`
con lo que acabas de poner:

```properties
storePassword=la que pusiste
keyPassword=la que pusiste
keyAlias=ride
storeFile=../ride-publicacion.jks
```

Ese archivo y el `.jks` **no entran en el repositorio** — ya están en
`.gitignore`. A partir de ahí, `flutter build apk --release` firma de verdad
sola; sin el archivo sigue usando la de depuración, así que nadie se queda sin
poder compilar.

Comprobar cómo quedó firmada una APK:

```bash
apksigner verify --print-certs -v build/app/outputs/flutter-apk/app-release.apk
```

Si dice `CN=Android Debug`, no es publicable.

### 3. El cobro con PayPal, a producción

La cuota del chofer está configurada contra **sandbox**: funciona, pero con
dinero de mentira. Para cobrar de verdad hay que cambiar los cinco secretos por
los de Live y crear allí el plan. El código ya está listo para Live; los pasos
están en [CUOTA.md](CUOTA.md#pasar-a-producción-live).

Mientras siga en sandbox, nadie paga: los choferes trabajan con el mes de
cortesía, y **cuando venza se bloquean todos a la vez**.

### 4. El cobro del viaje

Resuelto: efectivo y transferencia, sin depender de ninguna pasarela. DeUna se
retiró. El detalle está en [PAGOS.md](PAGOS.md).

### 5. Contraseñas filtradas: hace falta plan Pro

Supabase Auth puede rechazar contraseñas que ya se filtraron, contrastándolas
con HaveIBeenPwned. **No es un interruptor gratis**: la propia documentación dice
que está disponible del plan Pro en adelante, y la organización RIDE está en el
gratuito. Comprobado el 2026-09-10.

El aviso del linter de seguridad de Supabase va a seguir saliendo mientras tanto,
y no es que esté mal configurado: es que no se puede configurar.

Lo que sí se puede sin pagar está **hecho** desde el 2026-09-10, en
*Authentication → Providers → Email*:

- **10 caracteres** como mínimo.
- **Los cuatro tipos**: minúscula, mayúscula, número y símbolo.

`Validators.password` pide exactamente lo mismo, y no por casualidad: la lista
de símbolos que acepta la app está copiada de la que devuelve el servidor
—`` !@#$%^&*()_+-=[]{};'\:"|<>?,./`~ ``—, comprobada contra un intento de
registro real. Si el panel y el validador se separan, el usuario escribe una
contraseña que la app aprueba y el servidor rechaza con un mensaje que no dice
qué falta.

> **Si alguien cambia esos ajustes en el panel, hay que cambiar
> `Validators.password`** en la misma tanda. Las pruebas del grupo
> «Contrasenas» fijan las cuatro condiciones y el mensaje de cada una.
>
> A quien ya tenga cuenta no se le echa: puede seguir entrando con su contraseña
> actual aunque no cumpla lo nuevo. El requisito se aplica al registrarse y al
> cambiarla.

### 6. La ubicación del chofer en segundo plano: declararla en Play Console

Desde la 1.0.0+9, mientras el chofer está en línea o lleva un viaje, la app
mantiene un servicio en primer plano de tipo `location` con una notificación
fija («Ride está compartiendo tu ubicación»). Sin él, Android suspendía la app
al abrir Waze o apagar la pantalla, y el chofer dejaba de enviar su posición.

- **No pide la ubicación «todo el tiempo»** (`ACCESS_BACKGROUND_LOCATION`): le
  basta el permiso «mientras se usa», porque el servicio arranca con la app
  delante.
- **Play Console lo pregunta.** En *Contenido de la app → Permisos de servicio
  en primer plano* hay que declarar el tipo `location`, explicar para qué es y,
  normalmente, subir un vídeo corto: ponerse en línea, cambiar a otra app y
  enseñar la notificación. Sin esa declaración la revisión rechaza la versión.
- **Probarlo en un teléfono antes de publicar:** ponerse en línea, abrir Waze
  cinco minutos y comprobar en la web que la posición siguió moviéndose.

### 7. Los correos y a dónde vuelven

Los correos de acceso salen por Brevo (SMTP configurado en Supabase: 300 al día
en el plan gratuito, unos 9000 al mes). Pero **a dónde vuelve el enlace lo
decide Supabase**, no Brevo: *Authentication → URL Configuration*.

- **Site URL:** `https://rideviajes.com.ec`
- **Redirect URLs:** `https://rideviajes.com.ec/**`,
  `https://www.rideviajes.com.ec/**` y `ride://login-callback`, que es el de la
  app.

Si una dirección no está en la lista, Supabase manda al Site URL y la
recuperación de contraseña acaba en una página que no es. Después, pedir una
recuperación real y abrir el enlace: si Brevo tiene el seguimiento de clics
activado, reescribe los enlaces por un dominio suyo, y conviene apagarlo para
estos correos.

### 8. Antes de abrir al público

- **Un viaje completo con un chofer de rol `driver`**, nunca con un superadmin:
  los superadmin ven todos los perfiles y se saltan zona y cuota, y por eso
  nadie vio que un chofer real no llegaba a ver el viaje que aceptaba. Con dos
  teléfonos: aceptar, ver la ruta y el nombre del pasajero, dictar el código, ver
  al chofer moverse desde el teléfono del pasajero (con Waze abierto encima),
  cerrar en el destino, cobrar en efectivo y por transferencia con comprobante,
  calificar y escribir en el chat. Repetirlo en la web.
- **`infra/sql/pruebas/permisos.sql`**: pasarlo en el SQL Editor. Vacío quiere
  decir todo en orden. Hay que pasarlo tras cada migración: así se vio que dos
  habían reabierto permisos sin que nadie lo notara.
- **`infra/sql/limpiar-datos-de-prueba.sql`**: borra los viajes, pagos y avisos
  de las pruebas. Termina en `ROLLBACK`; se cambia por `COMMIT` cuando los
  números cuadren, y siempre después de una copia.

## Compilar para publicar

```bash
flutter build appbundle --release
```

Play Store quiere un **App Bundle** (`.aab`), no un APK: reparte a cada teléfono
solo lo que necesita. Los APK siguen valiendo para instalar a mano.

```bash
flutter build apk --release --split-per-abi
```
