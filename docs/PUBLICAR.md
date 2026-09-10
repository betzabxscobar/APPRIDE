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
los de Live y crear allí el plan. Los pasos están en [CUOTA.md](CUOTA.md).

Mientras siga en sandbox, nadie paga: los choferes trabajan con el mes de
cortesía, y **cuando venza se bloquean todos a la vez**.

### 4. El cobro con DeUna

Sin credenciales, el pasajero solo puede pagar en efectivo. Es una decisión de
alcance, no un fallo. Está todo escrito y esperando en [PAGOS.md](PAGOS.md).

### 5. Contraseñas filtradas

Supabase Auth puede rechazar contraseñas que ya se filtraron, contrastándolas
con HaveIBeenPwned. Es un interruptor del panel —*Authentication → Policies*—,
no código. Para una app que guarda viajes, dirección de casa y método de pago,
vale la pena.

## Compilar para publicar

```bash
flutter build appbundle --release
```

Play Store quiere un **App Bundle** (`.aab`), no un APK: reparte a cada teléfono
solo lo que necesita. Los APK siguen valiendo para instalar a mano.

```bash
flutter build apk --release --split-per-abi
```
