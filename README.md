# Ride

App móvil de Ride en Flutter. La bienvenida, el inicio de sesión y el registro
replican pantalla por pantalla los de WEB-RIDE (`src/App.tsx`), con la misma
paleta, las mismas tipografías (Sora y Plus Jakarta Sans) y las mismas reglas
de validación.

Los dos clientes comparten autenticación, perfiles, viajes, flota, pagos,
notificaciones y políticas de seguridad en el mismo proyecto de Supabase.

La superficie que consume la app —funciones, tablas, Realtime y Storage— está
documentada en [`docs/API.md`](docs/API.md). El mapa, en
[`docs/MAPA.md`](docs/MAPA.md); el buscador de direcciones, en
[`docs/BUSCADOR.md`](docs/BUSCADOR.md); los precios, en
[`docs/TARIFAS.md`](docs/TARIFAS.md); el cobro con DeUna, en
[`docs/PAGOS.md`](docs/PAGOS.md).

## Credenciales del equipo administrativo

Las contraseñas temporales **no están en el código**. Se pasan al compilar
desde `config/credenciales-administrativas.json`, un archivo que git ignora.

1. Copia `config/credenciales-administrativas.example.json` como
   `config/credenciales-administrativas.json`.
2. Pon las contraseñas que se entregaron por separado.
3. Compila o corre las pruebas apuntando a ese archivo:

```sh
flutter build apk --release --dart-define-from-file=config/credenciales-administrativas.json
flutter test --dart-define-from-file=config/credenciales-administrativas.json
```

Sin ese archivo la app compila y funciona igual, solo que sin cuentas
administrativas: quien intente entrar con uno de esos correos recibe el mismo
mensaje que un correo inexistente. Las pruebas que dependen de ellas se marcan
como omitidas.

Cuando exista la base de datos, estas cuentas pasan a Supabase, se activa
`mustChangePassword` y vuelve a usarse la pantalla de primer acceso.

## Cuentas de prueba

| Rol | Correo | Contraseña |
|---|---|---|
| Pasajero | pasajero@ride.app | Ride1234 |
| Conductor | conductor@ride.app | Ride1234 |

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

El APK sale en `build/app/outputs/flutter-apk/app-release.apk`. Hoy se firma
con la clave de depuración (ver `android/app/build.gradle.kts`): sirve para
instalarlo a mano, no para publicarlo en Play Store.

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
2. Sube licencia, SOAT y matrícula desde la cámara o la galería.
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
2. Registra efectivo, elige su opción principal o elimina una opción que no tenga pagos asociados.
3. La interfaz informa que las tarjetas requieren una futura pasarela de tokenización.

**Resultado:** la app no solicita ni almacena números de tarjeta y solo presenta
métodos respaldados por la base de datos.

### CU-A14. Configurar la cuenta

**Actor:** cualquier usuario autenticado.

1. El usuario abre **Configuración** desde su hoja de cuenta.
2. Elige el tema —el del sistema, claro u oscuro— y la elección queda guardada
   en el teléfono.
3. Cambia su foto de perfil, su nombre y su teléfono.
4. Para cambiar el correo o la contraseña, confirma antes su contraseña actual.

**Resultado:** el perfil queda actualizado. El correo nuevo solo entra en vigor
cuando el usuario abre el enlace de confirmación; hasta entonces sigue entrando
con el anterior. El rol no se puede cambiar desde aquí: lo impide el trigger
`prevent_role_self_edit()`.

### CU-A15. Revisar y aprobar a un conductor

**Actor:** administrador o superadministrador.

1. El usuario entra en **Conductores** y filtra por estado.
2. Abre la ficha de un chofer: sus datos de contacto, sus vehículos con placa y
   sus cuatro documentos —cédula, licencia, SOAT y matrícula—.
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

## Alcance actual

- Los seis módulos del panel administrativo móvil están conectados: **Resumen**,
  **Usuarios**, **Conductores**, **Viajes**, **Tarifas** y **Soporte**. Ya no
  queda ninguna pantalla de espera.
- La recuperación abre el navegador porque aún no están configurados los enlaces
  profundos que devolverían al usuario directamente a la aplicación. Lo mismo
  vale para el enlace que confirma un cambio de correo.
- Pasajero y conductor disponen de un mapa visual con ubicación, puntos del
  viaje, posición del conductor y ruta por calles cuando OSRM responde.
- El mapa usa teselas **vectoriales** de OpenFreeMap con estilos propios para
  claro y oscuro, sin claves ni cuotas. Los detalles están en
  [`docs/MAPA.md`](docs/MAPA.md).
- **No hay pasarela de pagos.** El único método real es el efectivo. La tarjeta
  existe en el modelo de datos, pero registrarla exige la tokenización de una
  pasarela: la app nunca pide ni almacena un número de tarjeta.
- El precio siempre se calcula en Supabase; la distancia de OSRM se usa para
  presentar la ruta y no autoriza al cliente a fijar la tarifa.
- El servidor público de OSRM sirve para desarrollo. Para producción debe
  configurarse uno propio siguiendo [`infra/osrm/README.md`](infra/osrm/README.md).
- Un documento subido en PDF se identifica pero no se previsualiza en la
  revisión: haría falta un visor de PDF y hoy no hay ninguno en el proyecto.
- El seguimiento del chofer se refresca cada 30 segundos mientras la aplicación
  está abierta. No hay rastreo en segundo plano: con la app cerrada, el auto
  deja de reportar posición hasta que se vuelve a abrir.

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
