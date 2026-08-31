# Ride

App móvil de Ride en Flutter. La bienvenida, el inicio de sesión y el registro
replican pantalla por pantalla los de WEB-RIDE (`src/App.tsx`), con la misma
paleta, las mismas tipografías (Sora y Plus Jakarta Sans) y las mismas reglas
de validación.

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

```sh
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
2. Define el origen con el GPS o el catálogo y selecciona un destino disponible.
3. El sistema calcula en el servidor la distancia y la tarifa estimada.
4. El pasajero confirma la cotización.

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

1. El conductor informa sucesivamente que va en camino, llegó al origen e inició el viaje.
2. Al terminar, selecciona **Finalizar viaje**.
3. El sistema liquida la tarifa y cierra el recorrido.
4. El conductor puede calificar al pasajero una sola vez.

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
2. El sistema ofrece únicamente las vistas habilitadas por su rol y vehículo.
3. El usuario cambia de vista o regresa a la correspondiente a su cuenta.

**Resultado:** cambia la pantalla, pero no el rol real ni los permisos en Supabase.

### CU-A10. Configurar la cuenta

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

### CU-A11. Revisar y aprobar a un conductor

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

### CU-A12. Ver la ruta del viaje

**Actor:** pasajero y conductor, a la vez.

1. Al aceptarse un viaje, ambos ven el mismo mapa con dos trazados: el camino
   del chofer hasta el punto de recogida —a rayas— y el del viaje hasta el
   destino.
2. La posición del chofer se refresca mientras dura el viaje.
3. Al iniciarse el recorrido, el tramo de recogida desaparece.

**Resultado:** las dos partes ven por dónde va el auto y cuánto falta.

### CU-A13. Recuperar el viaje tras cerrar la app

**Actor:** pasajero o conductor con un viaje en marcha.

1. El usuario cierra la aplicación durante un viaje.
2. Al volver a abrirla, la sesión abierta se salta la pantalla de bienvenida.
3. La aplicación reabre sola el viaje activo, con su ruta ya dibujada.

**Resultado:** no se pierde el seguimiento. El viaje siempre estuvo en Postgres;
lo que faltaba era el camino de vuelta y una copia local para pintarlo sin
esperar a la red.

## Alcance actual

- En el panel administrativo móvil están conectados **Resumen**, **Usuarios** y
  **Conductores**; Viajes, Tarifas y Soporte siguen siendo pantallas de espera.
- La recuperación abre el navegador porque aún no están configurados los enlaces
  profundos que devolverían al usuario directamente a la aplicación. Lo mismo
  vale para el enlace que confirma un cambio de correo.
- Un documento subido en PDF se identifica pero no se previsualiza en la
  revisión: haría falta un visor de PDF y hoy no hay ninguno en el proyecto.
- El seguimiento del chofer se refresca cada 30 segundos mientras la aplicación
  está abierta. No hay rastreo en segundo plano: con la app cerrada, el auto
  deja de reportar posición hasta que se vuelve a abrir.
