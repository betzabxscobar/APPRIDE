# Ride

App móvil de Ride en Flutter. La bienvenida, el inicio de sesión y el registro
replican pantalla por pantalla los de WEB-RIDE (`src/App.tsx`), con la misma
paleta, las mismas tipografías (Sora y Plus Jakarta Sans) y las mismas reglas
de validación.

Los dos clientes comparten autenticación, perfiles, viajes, flota, pagos,
notificaciones y políticas de seguridad en el mismo proyecto de Supabase.

La equivalencia funcional con WEB-RIDE se revisó el **8 de septiembre de
2026**. La web incluye los flujos de pasajero, conductor y administración de la
app, incluido el detalle completo de un viaje administrativo. Las diferencias
restantes corresponden al entorno: permisos móviles, enlaces profundos,
ubicación en segundo plano y notificaciones con la aplicación cerrada. Las dos
muestran al pie del acceso los mismos términos y condiciones.

La superficie que consume la app —funciones, tablas, Realtime y Storage— está
documentada en [`docs/API.md`](docs/API.md). El mapa, en
[`docs/MAPA.md`](docs/MAPA.md); el buscador de direcciones, en
[`docs/BUSCADOR.md`](docs/BUSCADOR.md); los precios, en
[`docs/TARIFAS.md`](docs/TARIFAS.md); cómo se cobra un viaje, en
[`docs/PAGOS.md`](docs/PAGOS.md); la cuota mensual que paga el chofer, en
[`docs/CUOTA.md`](docs/CUOTA.md); lo que se le exige a un chofer, en
[`docs/CHOFERES.md`](docs/CHOFERES.md). Lo que falta para publicar en Play
Store, en [`docs/PUBLICAR.md`](docs/PUBLICAR.md).

## Cuentas del equipo

Las cuentas administrativas viven en Supabase Auth, como las de cualquier
usuario: no hay ninguna contraseña en el código ni en la APK. Cada persona
cambia la suya desde Ajustes, con la misma regla que exige Supabase: 10
caracteres y los cuatro tipos.

`config/credenciales-administrativas.json` (ignorado por git) ya solo guarda
claves de servicios para compilar, hoy `TOMTOM_KEY`, y es opcional:

```sh
flutter build apk --release --dart-define-from-file=config/credenciales-administrativas.json
```

Sin él la app compila igual, y la búsqueda de direcciones usa Photon. Las
contraseñas temporales que quedaron en el commit `fdc2b99` se cambiaron el
2026-09-11: lo que hay en el historial ya no abre nada.

## Cuentas de prueba

No se publican aquí. En producción, una cuenta con la contraseña escrita en un
repositorio público es una cuenta de cualquiera. Las de prueba se crean y se
borran desde el panel de Supabase cuando hacen falta.

## Comandos

Requisitos: Flutter con Dart 3.11 o posterior, Android Studio o Xcode según la
plataforma y un dispositivo o emulador configurado.

```sh
flutter pub get          # instalar dependencias
flutter run              # ejecutar en el dispositivo conectado
flutter test             # pruebas
flutter analyze          # análisis estático
flutter build apk --release
```

El APK sale en `build/app/outputs/flutter-apk/app-release.apk`. La versión
actual es **1.0.0+10** (`pubspec.yaml`) con el identificador
`com.rideviajes.ride`.

Mientras no exista `android/key.properties` se firma con la clave de depuración:
sirve para instalarla a mano, no para Play Store. La clave de publicación se
crea una sola vez con `python tool/crear_firma.py` (pide la contraseña sin
mostrarla), y a partir de ahí `flutter build appbundle --release` firma de
verdad. Guarda copia del `.jks` y de la contraseña en dos sitios: sin ellos no se
puede publicar ninguna actualización nunca más. Ver
[`docs/PUBLICAR.md`](docs/PUBLICAR.md).

## Casos de uso implementados

Los siguientes flujos corresponden a las funciones conectadas en la versión
actual de `main`.

### CU-A01. Registrar una cuenta

**Actor:** pasajero o conductor.

1. El usuario abre el registro, elige si desea viajar o conducir e ingresa sus datos.
2. El sistema crea la cuenta en Supabase y solicita confirmar el correo.
3. Tras la confirmación, el usuario puede iniciar sesión con el rol elegido.

**Resultado:** se crea el perfil; el registro público no permite elegir roles administrativos.

### CU-A02. Iniciar y cerrar sesión

**Actor:** usuario registrado.

1. El usuario ingresa correo y contraseña.
2. El sistema valida las credenciales, carga el perfil y abre la vista de su rol.
3. La sesión se restaura al volver a abrir la aplicación.
4. El usuario puede cerrar sesión desde su cuenta o desde el panel administrativo.

**Resultado:** el usuario accede a la aplicación con los permisos de su perfil.

### CU-A03. Solicitar la recuperación de contraseña

**Actor:** usuario registrado.

1. El usuario selecciona **¿Olvidaste tu contraseña?** e ingresa su correo.
2. El sistema solicita a Supabase el envío del enlace de recuperación.
3. El usuario completa el cambio desde el navegador y vuelve a iniciar sesión.

**Resultado:** se inicia una recuperación sin revelar si el correo está registrado.

### CU-A04. Solicitar un viaje

**Actor:** pasajero autenticado.

1. El pasajero selecciona **Pedir un viaje**.
2. Define el origen con el GPS o el buscador y selecciona un destino.
3. Puede añadir una referencia escrita del punto de recogida —«portón verde,
   junto a la farmacia»— para que el chofer no dé vueltas.
4. El sistema cotiza en el servidor los cuatro tipos de vehículo con la misma
   distancia (`cotizar_categorias`) y el pasajero elige uno.
5. El pasajero confirma la cotización.

**Resultado:** el viaje queda en búsqueda de conductor y se abre su seguimiento.

### CU-A05. Seguir, cancelar y calificar un viaje

**Actor:** pasajero con un viaje registrado.

1. El pasajero abre su viaje activo o uno de su historial.
2. La pantalla actualiza el estado mediante Supabase Realtime.
3. Antes de iniciar el recorrido, el pasajero puede cancelar el viaje.
4. Al finalizar, puede calificar al conductor una sola vez.

**Resultado:** el pasajero conoce el avance y deja registrada su valoración.

### CU-A06. Ponerse disponible y aceptar una solicitud

**Actor:** conductor aprobado con vehículo activo.

1. El conductor abre **Viajes** y activa su disponibilidad.
2. El sistema muestra las solicitudes que puede atender.
3. El conductor selecciona **Aceptar ruta**.
4. La base de datos asigna el viaje solo si ningún otro conductor lo tomó antes.

**Resultado:** el conductor queda asignado al viaje y deja de recibir otras solicitudes.

### CU-A07. Realizar y finalizar un viaje

**Actor:** conductor asignado.

1. El conductor informa sucesivamente que va en camino y que llegó al origen.
2. Para iniciar el recorrido pide al pasajero el código de seis dígitos y lo
   escribe (ver CU-A19); sin él, el viaje no arranca.
3. Al terminar, selecciona **Finalizar viaje**.
4. El sistema liquida la tarifa y cierra el recorrido.
5. El conductor puede calificar al pasajero una sola vez.

**Resultado:** el viaje y su cobro quedan finalizados con su historial de estados.

### CU-A08. Consultar usuarios desde el panel móvil

**Actor:** administrador o superadministrador.

1. El usuario completa el cambio de contraseña inicial si corresponde.
2. Entra en **Resumen** o **Usuarios**.
3. El sistema muestra métricas y los perfiles visibles para su rol.

**Resultado:** un administrador consulta pasajeros, conductores y cuentas permitidas;
solo el superadministrador puede ver perfiles de superadministradores.

### CU-A09. Cambiar entre vistas autorizadas

**Actor:** usuario con acceso a más de una vista.

1. El usuario abre el selector de panel.
2. El sistema ofrece únicamente las vistas habilitadas por su rol.
3. El usuario cambia de vista o regresa a la correspondiente a su cuenta.

Administrador y superadministrador llegan los dos a la vista de usuario y a la
de chofer; la de superadministrador sigue siendo solo para él.

**Resultado:** cambia la pantalla, pero no el rol real ni los permisos en
Supabase. Los dos pueden pedir un viaje de verdad desde la vista de usuario
—`solicitar_viaje` no mira el rol—, pero conducir es otra cosa: ponerse en línea
y aceptar carreras solo lo admiten `validar_disponibilidad_conductor_real()` y
`aceptar_viaje` para `driver` y `superadmin`. Un administrador abre la vista de
chofer para revisarla y la pantalla se lo dice con esas palabras.

### CU-A10. Gestionar vehículos y documentos

**Actor:** conductor autenticado.

1. El conductor abre su perfil, registra o edita un vehículo y elige cuál queda en servicio.
2. Registra su cédula, su código dactilar y el tipo de licencia que tiene.
3. Sube su cédula, su licencia y su foto; y de **cada** vehículo, la matrícula,
   el SPPAT, la revisión técnica y una foto, con su fecha de caducidad.
3. Consulta si cada documento está pendiente, aprobado o rechazado.
4. Puede abrir el archivo privado mediante un enlace temporal y reemplazarlo si es necesario.

**Resultado:** el conductor puede completar desde el móvil los requisitos que
la administración revisa antes de habilitarlo.

### CU-A11. Buscar y guardar lugares en el mapa

**Actor:** pasajero autenticado.

1. El pasajero busca una dirección o toca directamente un punto del mapa.
2. La búsqueda se acota a Ecuador y usa TomTom cuando hay una clave válida; en
   caso contrario utiliza Photon/OpenStreetMap, que en Quito responde peor.
3. Puede guardar lugares como favoritos y reutilizarlos en viajes posteriores.
4. La app dibuja el recorrido por calles entre origen y destino con OSRM.

**Resultado:** el pasajero elige puntos reales y conserva sus lugares frecuentes.

### CU-A12. Consultar notificaciones

**Actor:** usuario autenticado.

1. El usuario abre la campana desde su pantalla principal.
2. Consulta los avisos generados por cambios de sus viajes y su cuenta.
3. La aplicación recibe nuevas notificaciones mediante Realtime y permite marcarlas como leídas.

**Resultado:** el usuario conoce los cambios relevantes sin consultar viajes ajenos.

### CU-A13. Administrar métodos de pago

**Actor:** pasajero autenticado.

1. El pasajero abre **Métodos de pago** desde su cuenta.
2. Registra efectivo o transferencia, elige su opción principal o elimina una
   opción que no tenga pagos asociados.
3. Las tarjetas siguen requiriendo una futura pasarela de tokenización.

**Resultado:** la app no solicita ni almacena números de tarjeta y solo presenta
métodos respaldados por la base de datos.

### CU-A13b. Pagar el viaje por transferencia

**Actor:** pasajero con transferencia como método principal, y su chofer.

1. Durante el viaje, el pasajero abre **Pagar por transferencia** y ve las
   cuentas del chofer, con el número listo para copiar.
2. Transfiere desde la app de su banco, adjunta la foto del comprobante y pulsa
   **Ya transferí**.
3. Al chofer le llega el aviso, mira su cuenta y contrasta con el comprobante.
4. Confirma que le llegó, y solo entonces puede cerrar el viaje.

**Resultado:** el cobro queda comprobado por quien de verdad puede verlo —el
chofer, en su banco— y con la foto guardada por si más tarde se discute. **Ride
no toca ese dinero**: va directo de un banco a otro. El detalle está en
[`docs/PAGOS.md`](docs/PAGOS.md).

### CU-A14. Configurar la cuenta

**Actor:** cualquier usuario autenticado.

1. El usuario abre **Configuración** desde su hoja de cuenta.
2. Elige el tema —el del sistema, claro u oscuro— y la elección queda guardada
   en el teléfono.
3. Cambia su foto de perfil, su nombre y su teléfono.
4. Para cambiar el correo o la contraseña, confirma antes su contraseña actual.

**Resultado:** el perfil queda actualizado. El correo nuevo solo entra en vigor
cuando el usuario abre el enlace de confirmación; hasta entonces sigue entrando
con el anterior. De su perfil, una persona solo puede cambiar el nombre, el
teléfono y la foto: la base no le deja tocar su rol, su correo en el perfil ni
si la cuenta está activa, aunque se salte la app.

### CU-A15. Revisar y aprobar a un conductor

**Actor:** administrador o superadministrador.

1. El usuario entra en **Conductores** y filtra por estado.
2. Abre la ficha de un chofer: sus datos de contacto, sus vehículos con placa y
   sus papeles: los suyos y los de cada vehículo.
3. Abre cada documento a pantalla completa y lo aprueba o lo rechaza.
4. Con los cuatro aprobados y al menos un vehículo, aprueba la cuenta.

**Resultado:** el chofer puede ponerse en línea. El servidor comprueba las
mismas condiciones en `revisar_conductor`, así que aprobar sin los papeles
completos rebota aunque se manipule el cliente. Cada decisión le llega al chofer
como notificación.

### CU-A16. Ver la ruta del viaje

**Actor:** pasajero y conductor, a la vez.

1. Al aceptarse un viaje, ambos ven el mismo mapa con dos trazados: el camino
   del chofer hasta el punto de recogida —a rayas— y el del viaje hasta el
   destino.
2. La posición del chofer se refresca mientras dura el viaje.
3. Al iniciarse el recorrido, el tramo de recogida desaparece.

**Resultado:** las dos partes ven por dónde va el auto y cuánto falta.

### CU-A17. Recuperar el viaje tras cerrar la app

**Actor:** pasajero o conductor con un viaje en marcha.

1. El usuario cierra la aplicación durante un viaje.
2. Al volver a abrirla, la sesión abierta se salta la pantalla de bienvenida.
3. La aplicación reabre sola el viaje activo, con su ruta ya dibujada.

**Resultado:** no se pierde el seguimiento. El viaje siempre estuvo en Postgres;
lo que faltaba era el camino de vuelta y una copia local para pintarlo sin
esperar a la red.

### CU-A18. Hablar con la otra parte del viaje

**Actor:** pasajero y conductor asignado.

1. Con el viaje ya aceptado, cualquiera de los dos abre el chat desde el
   seguimiento.
2. Escribe un mensaje corto: «estoy en la puerta de atrás», «ya salgo», «me
   dejé la mochila».
3. El otro lo recibe por Realtime y el botón enseña cuántos quedan sin leer.

**Resultado:** las dos partes se coordinan sin darse el número de teléfono. Los
mensajes cuelgan del viaje, no de las personas: fuera de un viaje no hay bandeja
que abrir, y el botón no aparece hasta que hay chofer asignado.

### CU-A19. Verificar el inicio con el código de seis dígitos

**Actor:** pasajero y conductor asignado.

1. Cuando el chofer marca que llegó al origen, la base genera un código de seis
   dígitos.
2. El pasajero lo ve en su pantalla de seguimiento. El chofer no puede leerlo:
   la política `codigos_solo_el_pasajero` no le entrega la fila.
3. El pasajero se lo dicta y el chofer lo escribe para iniciar el recorrido.
4. `avanzar_viaje` rechaza el salto si el código no coincide.

**Resultado:** el viaje solo arranca con el pasajero correcto dentro del auto. El
código vive en su propia tabla y no en una columna de `viajes` porque RLS filtra
filas, no columnas.

### CU-A20. Consultar el historial de viajes

**Actor:** pasajero o conductor autenticado.

1. El usuario abre la pestaña **Viajes**.
2. Consulta sus viajes del más nuevo al más viejo, con su estado, su tipo de
   vehículo y su total.
3. Puede abrir cualquiera para volver a ver su seguimiento.

**Resultado:** cada quien ve los suyos. La pantalla es la misma para los dos
roles porque las políticas RLS ya limitan las filas; lo único que cambia es a
quién se nombra en cada fila.

### CU-A21. Consultar las ganancias

**Actor:** conductor autenticado.

1. El conductor abre la pestaña **Ganancias**.
2. Consulta lo de hoy, la semana, el mes y el total desde que empezó: viajes
   cerrados, lo que pagaron los pasajeros, lo que le queda y la comisión.

**Resultado:** el chofer sabe cuánto lleva ganado. Los números los calcula
`ganancias_conductor` en Postgres, no el teléfono, y cada viaje conserva el
reparto de la tarifa con la que se cobró: cambiar el porcentaje hoy no reescribe
lo ya ganado.

### CU-A22. Abrir un caso de soporte

**Actor:** pasajero o conductor autenticado.

1. El usuario abre **Soporte** desde su configuración, o desde un viaje concreto.
2. Elige una categoría, escribe el asunto y el mensaje.
3. Consulta el estado de sus casos y la respuesta de la administración.

**Resultado:** queda registrado el caso. Si se abrió desde un viaje, queda atado
a él y la administración no tiene que preguntar de cuál se trata. El autor no
puede editarlo después: cambiar el asunto ya respondido dejaría la respuesta sin
sentido.

### CU-A23. Atender los casos de soporte

**Actor:** administrador o superadministrador.

1. El usuario entra en **Soporte** y filtra por estado.
2. Los casos que llevan más esperando salen primero: es una cola, no un muro.
3. Abre uno, ve quién lo escribió y responde.

**Resultado:** el caso queda respondido y su autor lee la respuesta en la app.
Responder es solo de administración; cada quien lee los suyos y la
administración los lee todos.

### CU-A24. Supervisar los viajes de la plataforma

**Actor:** administrador o superadministrador.

1. El usuario entra en **Viajes** y filtra por estado: buscando, en curso,
   finalizados o cancelados.
2. Abre cualquiera para ver su seguimiento completo.

**Resultado:** la administración ve todos los viajes. No lo filtra el cliente:
`viajes_participante` incluye `es_administrativo()`, así que un pasajero que
llamara a lo mismo seguiría viendo solo los suyos.

### CU-A25. Ajustar tarifas y tipos de vehículo

**Actor:** administrador o superadministrador.

1. El usuario entra en **Tarifas** y ve las cuatro franjas —estándar, hora pico
   de mañana, hora pico de tarde y nocturna— con sus horas, sus días y sus
   números.
2. Cambia el arranque, el costo por kilómetro, la carrera mínima o el reparto
   del chofer, con el cálculo de un viaje de ejemplo delante para no mover un
   número a ciegas.
3. Ajusta también los tipos de vehículo y su multiplicador.

**Resultado:** el precio cambia sin publicar una versión nueva. La app valida
antes de salir a la red —nada negativo, reparto entre 1 y 100 %, carrera mínima
no menor que el arranque— y las políticas `tarifas_admin` y `categorias_admin`
rechazan la escritura de cualquier otra cuenta. Los valores y de dónde salen
están en [`docs/TARIFAS.md`](docs/TARIFAS.md).

### CU-A26. Probar el flujo de conductor como superadministrador

**Actor:** superadministrador.

1. El usuario cambia a la vista de conductor.
2. `preparar_chofer_superadmin` le crea —o le aprueba— su fila en `conductores`.
3. Registra un vehículo y lo pone en servicio.

**Resultado:** recorre el ciclo entero sin esperar a que alguien apruebe su
propia cuenta. La función comprueba el rol en el servidor y rebota con 42501
desde cualquier otra; el vehículo sigue haciendo falta, porque eso no es un
permiso: un viaje no puede arrancar sin auto asignado.

> **No sirve para dar por probado el flujo del chofer.** Un superadministrador
> ve todos los perfiles y se salta zona y cuota, así que con él todo funciona
> aunque para un chofer real no funcione. Pasó de verdad: hasta el 2026-09-11 un
> chofer de rol `driver` no veía el viaje que aceptaba, y nadie lo notó porque
> todas las pruebas se hacían como superadmin. Probar siempre con una cuenta de
> chofer normal.

### CU-A27. Pagar la cuota mensual para recibir viajes

**Actor:** conductor.

1. El chofer abre «Mi cuota mensual» desde su hoja de inicio.
2. El panel muestra si está al día, cuántos días le quedan y hasta cuándo.
3. Pulsa pagar y la app abre PayPal con la suscripción ya creada a su nombre.
4. PayPal cobra los 15 USD y avisa al servidor, que activa el mes.

**Resultado:** puede ponerse en línea y aceptar viajes. Sin la cuota al día el
servidor le rebota las tres cosas —encenderse, ver solicitudes y aceptar—, y el
corte vive en Postgres, no en la app. Los choferes que ya estaban tienen un mes
de cortesía; si pagan antes de que acabe, el mes pagado empieza donde termina la
cortesía y no pierden días. Dar de baja la suscripción no quita el mes ya
pagado, y un pago devuelto sí lo descuenta. El detalle está en
[`docs/CUOTA.md`](docs/CUOTA.md).

## Alcance actual

- Los seis módulos del panel administrativo móvil están conectados: **Resumen**,
  **Usuarios**, **Conductores**, **Viajes**, **Tarifas** y **Soporte**. Ya no
  queda ninguna pantalla de espera.
- Android e iOS registran `ride://login-callback` para que la recuperación de
  contraseña y la confirmación de correo puedan volver a la aplicación. También
  debe añadirse esa URL a la lista de redirecciones permitidas del proyecto de
  Supabase usado en cada entorno.
- Pasajero y conductor disponen de un mapa visual con ubicación, puntos del
  viaje, posición del conductor y ruta por calles cuando OSRM responde.
- El mapa usa teselas **vectoriales** de OpenFreeMap con estilos propios para
  claro y oscuro, sin claves ni cuotas. Los detalles están en
  [`docs/MAPA.md`](docs/MAPA.md).
- Efectivo y transferencia son los dos métodos disponibles. Con transferencia
  el pasajero paga desde la app de su banco a la cuenta del chofer, adjunta el
  comprobante y avisa; el chofer revisa su cuenta y confirma, y el viaje no se
  cierra hasta entonces. **Ride no toca ese dinero.** DeUna se retiró. La app
  nunca pide ni almacena un número de tarjeta.
- La cuota mensual del chofer —15 USD para recibir viajes— está aplicada en la
  base de datos y el corte está probado con un rol real. Las dos Edge Functions
  de PayPal (v22) están desplegadas y **configuradas contra sandbox**: funcionan
  con dinero de prueba. Para cobrar de verdad hay que poner las credenciales
  **Live** antes del **2026-10-09**, cuando vencen las cortesías de los choferes
  actuales. El código ya está listo; los pasos, en
  [`docs/CUOTA.md`](docs/CUOTA.md#pasar-a-producción-live).
- Pasajero y chofer no pueden escribir directamente en las tablas del viaje, del
  cobro ni del chat: todo pasa por funciones de Postgres que deciden precio,
  estado y quién puede qué. Cada uno ve su perfil y el de la otra persona de sus
  viajes, nada más. `infra/sql/pruebas/permisos.sql` lo comprueba y hay que
  pasarlo tras cada migración.
- El precio siempre se calcula en Supabase; la distancia de OSRM se usa para
  presentar la ruta y no autoriza al cliente a fijar la tarifa.
- El servidor público de OSRM sirve para desarrollo. Para producción debe
  configurarse uno propio siguiendo [`infra/osrm/README.md`](infra/osrm/README.md).
- Un documento subido en PDF se identifica pero no se previsualiza en la
  revisión: haría falta un visor de PDF y hoy no hay ninguno en el proyecto.
- El icono de la app es el logotipo de Ride, en las dos variantes que pide
  Android: adaptativo para Android 8 en adelante —fondo y logo en capas, para
  que cada launcher lo recorte con su forma— y clásico para los anteriores. Los
  PNG se regeneran desde `assets/images/LogoTipo.png` con
  `python tool/generar_iconos_android.py`. iOS sigue con el icono por defecto.
- Mientras el chofer está en línea o lleva un viaje, Android mantiene un
  servicio en primer plano con una notificación fija («Ride está compartiendo tu
  ubicación»), así que sigue reportando posición con Waze delante o la pantalla
  apagada. Basta el permiso «mientras se usa la app». En iOS todavía no: allí la
  posición se detiene con la app en segundo plano.

## Comprobaciones automáticas

Cada envío o propuesta de cambio hacia `main` ejecuta en GitHub Actions:

```sh
flutter pub get
flutter analyze
flutter test
```

Estas comprobaciones detectan errores de código y regresiones cubiertas por las
pruebas; no sustituyen una prueba manual del GPS, enlaces de correo, mapas,
notificaciones, cámara, archivos y permisos en dispositivos Android e iOS reales.

Estado local comprobado el **11 de septiembre de 2026**, con 1.0.0+10:
`flutter analyze` sin problemas, **235 pruebas aprobadas** y
`flutter build apk --release` correcto. En la base,
`infra/sql/pruebas/permisos.sql` sale vacío.

## Antes de producción

Revisado en la auditoría del 2026-09-11. En este orden:

1. **Un viaje completo con dos teléfonos y un chofer de rol `driver`**, nunca
   con un superadmin: aceptar, ver la ruta y el nombre del pasajero, dictar el
   código, ver al chofer moverse con Waze abierto encima, cerrar en el destino,
   cobrar en efectivo y por transferencia, calificar y usar el chat.
2. **Firmar la APK** con `python tool/crear_firma.py` y declarar en Play Console
   el servicio en primer plano de tipo `location`.
3. **Supabase → Authentication → URL Configuration**: Site URL
   `https://rideviajes.com.ec`; redirecciones esa, `www` y `ride://login-callback`.
   Después, probar recuperación y cambio de correo.
4. **PayPal Live** antes del 2026-10-09
   ([`docs/CUOTA.md`](docs/CUOTA.md#pasar-a-producción-live)).
5. **Limpiar los datos de prueba** con `infra/sql/limpiar-datos-de-prueba.sql`,
   después de una copia de la base.
6. Quitar el paso libre del superadmin como chofer (CU-A26) antes de abrir al
   público.

Para crecer: un servidor OSRM propio ([`infra/osrm`](infra/osrm/README.md)), FCM
y APNs si hacen falta avisos con la app cerrada, la ubicación en segundo plano
en iOS y un visor de PDF para la revisión de documentos.

## Configuración opcional

La app incluye valores públicos de Supabase para el entorno compartido. Pueden
sobrescribirse al compilar, junto con el buscador y el servidor de rutas:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://proyecto.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_clave \
  --dart-define=TOMTOM_KEY=clave_opcional \
  --dart-define=OSRM_URL=https://rutas.ejemplo.com
```

Sin `TOMTOM_KEY`, la búsqueda cae automáticamente a Photon. Sin `OSRM_URL`, usa
el servidor público de demostración. Nunca se debe compilar una clave
`service_role` dentro de la aplicación.
