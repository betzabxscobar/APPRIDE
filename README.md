# Ride

App móvil de Ride en Flutter. La bienvenida, el inicio de sesión y el registro
replican pantalla por pantalla los de WEB-RIDE (`src/App.tsx`), con la misma
paleta, las mismas tipografías (Sora y Plus Jakarta Sans) y las mismas reglas
de validación.

Los dos clientes comparten autenticación, perfiles, viajes, flota, pagos,
notificaciones y políticas de seguridad en el mismo proyecto de Supabase.

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
2. La búsqueda se limita a su región y usa TomTom cuando hay una clave válida;
   en caso contrario utiliza Photon/OpenStreetMap.
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

## Alcance actual

- En el panel administrativo móvil solo están conectados **Resumen** y **Usuarios**;
  Conductores, Viajes, Tarifas y Soporte son pantallas de espera.
- La recuperación abre el navegador porque aún no están configurados los enlaces
  profundos que devolverían al usuario directamente a la aplicación.
- Pasajero y conductor disponen de un mapa visual con ubicación, puntos del
  viaje, posición del conductor y ruta por calles cuando OSRM responde.
- El precio siempre se calcula en Supabase; la distancia de OSRM se usa para
  presentar la ruta y no autoriza al cliente a fijar la tarifa.
- El servidor público de OSRM sirve para desarrollo. Para producción debe
  configurarse uno propio siguiendo [`infra/osrm/README.md`](infra/osrm/README.md).

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
