# La API de Ride

**Ride no tiene servidor propio.** La app habla directo con Supabase: PostgREST
para las funciones y las tablas, Realtime para los avisos y Storage para los
archivos. No hay una capa intermedia que escribir ni que desplegar.

Eso obliga a una regla, y de ella sale todo lo demás:

> **El cliente no decide nada que importe.** El precio, el estado de un viaje y
> quién ve qué los fija Postgres. Un APK se descompila y se manipula; una
> función `security definer` con `auth.uid()` dentro, no.

Los servicios de `lib/services/` son envoltorios finos: traducen errores al
español y arman los parámetros. Ninguno decide permisos.

## Cómo se llama

Todas las funciones se invocan igual, y sus parámetros llevan el prefijo `p_`:

```dart
await Supabase.instance.client.rpc('cotizar_viaje', params: {
  'p_origen_lat': -0.1807, 'p_origen_lng': -78.4678,
  'p_destino_lat': -0.2299, 'p_destino_lng': -78.5249,
});
```

`RideService._rpc()` envuelve esa llamada y convierte la `PostgrestException` en
una `RideException` con el mensaje ya en español. Las funciones lanzan sus
errores en español a propósito, para que la app no tenga que mantener un
diccionario; `_traducir()` solo cubre los que genera Postgres por su cuenta
—claves duplicadas, violaciones de RLS, restricciones `check`—.

Códigos que devuelven las funciones y qué significan:

| Código | Qué pasó |
|---|---|
| `28000` | No hay sesión. `auth.uid()` vino en null. |
| `42501` | Hay sesión, pero esa cuenta no puede hacer eso. |
| `check_violation` | Un valor fuera de rango: un estado que no existe, un porcentaje imposible. |

## Viajes

El ciclo entero vive en Postgres. La app solo pide el siguiente paso.

| Función | Parámetros | Devuelve | Quién |
|---|---|---|---|
| `cotizar_viaje` | `p_origen_lat`, `p_origen_lng`, `p_destino_lat`, `p_destino_lng`, `p_distancia_km`, `p_tarifa_id`, `p_categoria` | fila con `total`, `gana_conductor`, `comision_app`, `aplico_minima` | cualquiera |
| `cotizar_categorias` | los cuatro puntos y `p_distancia_km` | una fila **por tipo de vehículo**, ya calculada | cualquiera |
| `solicitar_viaje` | origen y destino con su texto y su referencia, `p_distancia_km`, `p_categoria`, `p_origen_celda_h3_7`, `p_celdas_difusion` | `uuid` del viaje | pasajero |
| `aceptar_viaje` | `p_viaje_id` | `uuid` | chofer disponible |
| `avanzar_viaje` | `p_viaje_id`, `p_codigo` | el estado nuevo | el chofer del viaje |
| `finalizar_viaje` | `p_viaje_id` | el total cobrado | el chofer del viaje |
| `cancelar_viaje` | `p_viaje_id` | — | pasajero o chofer |
| `reportar_posicion` | `p_lat`, `p_lng`, `p_viaje_id`, `p_celda_h3_7`, `p_celda_h3_9` | — | chofer |

Detalles que no se ven en la tabla:

- **`cotizar_categorias` es una sola llamada, no cuatro.** Multiplicar el precio
  estándar por el factor de cada categoría en el cliente daría cifras que no
  cuadran con lo que se cobra: el redondeo y la carrera mínima no son lineales.
- **`p_distancia_km` es la distancia con la que se calculó el precio que el
  pasajero acaba de aceptar.** Sin ella el viaje se guardaría con otro importe.
  No es el cliente fijando la tarifa: la función recalcula con esa distancia y
  sus propios números.
- **Las celdas H3 las calcula la app** porque H3 no existe dentro de Postgres.
  Si van en null la difusión de la solicitud cae a PostGIS por radio, así que no
  romperlo no depende de que el teléfono coopere.
- **`avanzar_viaje` no acepta saltos.** La transición es `ACEPTADO` →
  `CONDUCTOR_EN_CAMINO` → `CONDUCTOR_EN_ORIGEN` → `EN_CURSO`, y el último paso
  exige `p_codigo`. El trigger `validar_transicion_viaje()` vigila lo mismo
  desde la tabla.
- **`reportar_posicion` acepta un viaje nulo a propósito.** Un chofer en línea
  sin viaje asignado también tiene que ser localizable: la difusión de
  solicitudes solo le llega si tiene una posición reciente.

Los valores de las tarifas y de dónde salen están en
[`TARIFAS.md`](TARIFAS.md).

## Chat

| Función | Parámetros | Devuelve |
|---|---|---|
| `enviar_mensaje` | `p_viaje_id`, `p_texto` | `uuid` del mensaje |
| `marcar_mensajes_leidos` | `p_viaje_id` | cuántos marcó |

Los mensajes cuelgan de un **viaje**, no de dos personas. Fuera de un viaje no
hay conversación que abrir, y eso no es una decisión de interfaz: una bandeja
abierta entre desconocidos es una vía de acoso. `enviar_mensaje` rebota si el
viaje todavía no tiene chofer.

## Flota y documentos

| Función | Parámetros | Devuelve |
|---|---|---|
| `registrar_vehiculo` | `p_placa`, `p_marca`, `p_modelo`, `p_anio`, `p_color`, `p_vehiculo_id`, `p_categoria` | `uuid` |
| `activar_vehiculo` | `p_vehiculo_id` | — |
| `registrar_documento` | ver «Choferes: identidad y papeles» | `uuid` |

`registrar_vehiculo` sirve para crear y para editar: con `p_vehiculo_id` en null
crea, con un id actualiza el que ya existe. **No basta con registrarlo**:
`activar_vehiculo` exige que la licencia del chofer habilite esa categoría y que
ese auto tenga sus cuatro papeles aprobados y sin caducar.

## Pagos

| Función | Parámetros | Devuelve | Quién |
|---|---|---|---|
| `registrar_metodo_pago` | `p_tipo`, `p_token`, `p_predeterminado` | `uuid` | pasajero |
| `elegir_metodo_predeterminado` | `p_metodo_id` | — | pasajero |
| `cobro_deuna` | `p_viaje_id` | `orden`, `monto`, `estado` | el pasajero del viaje |
| `confirmar_cobro_deuna` | `p_orden`, `p_pagado`, `p_datos` | `uuid` del pago | `service_role` o administración |

> **`p_token` no es un número de tarjeta y la base lo comprueba.**
> `registrar_metodo_pago` rechaza cualquier valor con forma de PAN. Los tipos
> que la app registra son `efectivo` y `deuna`, y ninguno guarda nada del
> pasajero; la tarjeta espera una pasarela que tokenice, y hasta entonces no hay
> formulario donde escribirla.

`cobro_deuna` devuelve el importe que hay que cobrar y fija el número de orden,
que es el mismo cada vez que se pide el QR de ese viaje. **La app no manda el
importe nunca**, y quien llama a Payválida es la Edge Function `cobro-deuna`,
que es la única que ve el `fixedhash`.

`confirmar_cobro_deuna` es lo que mueve dinero: marca el cobro y le abona al
chofer su parte, igual que el efectivo le carga la comisión. Es idempotente
porque un aviso de pasarela se reintenta. Todo el circuito, y las preguntas que
quedan abiertas con Payválida, están en [`PAGOS.md`](PAGOS.md).

## Choferes: identidad y papeles

| Función | Parámetros | Devuelve | Quién |
|---|---|---|---|
| `registrar_identidad_chofer` | `p_cedula`, `p_codigo_dactilar`, `p_licencia_tipo`, `p_licencia_caduca_el` | — | el propio chofer |
| `registrar_documento` | `p_tipo`, `p_url`, `p_vehiculo_id`, `p_numero`, `p_caduca_el` | `uuid` | el propio chofer |
| `revisar_documento` | `p_documento_id`, `p_aprobado`, `p_motivo` | estado | administración |
| `revisar_conductor` | `p_conductor_id`, `p_aprobado`, `p_motivo` | estado | administración |
| `papeles_que_faltan_chofer` | `p_conductor_id` (null = uno mismo) | `text[]` | el chofer o administración |
| `papeles_que_faltan_vehiculo` | `p_vehiculo_id` | `text[]` | el dueño o administración |
| `cedula_ecuatoriana_valida` | `p_cedula` | `boolean` | cualquiera autenticado |
| `licencia_habilita` | `p_licencia`, `p_categoria` | `boolean` | cualquiera autenticado |

> **Los papeles del vehículo son de un vehículo.** `matricula`, `SPPAT`,
> `revision_tecnica` y `foto_vehiculo` exigen `p_vehiculo_id`; `cedula`,
> `licencia` y `foto_perfil` lo rechazan. Un chofer con dos autos necesita dos
> matrículas, y hasta el 2026-09-03 la tabla no dejaba tenerlas.

> **`papeles_que_faltan_chofer()` es la única definición de «está completo».**
> La usan `revisar_conductor`, la pantalla del chofer y la de revisión. Si cada
> una contara por su cuenta, acabarían discrepando.

Rechazar exige motivo, y las caducidades se comprueban también al ponerse en
línea: aprobar es de una vez, pero un SPPAT caduca solo. Todo el circuito está
en [`CHOFERES.md`](CHOFERES.md).

## Ganancias

`ganancias_conductor()` no lleva parámetros: sabe quién llama por `auth.uid()`.
Devuelve una fila por periodo —`hoy`, `semana`, `mes`, `total`— con `viajes`,
`bruto`, `ganado` y `comision`.

Cada viaje conserva el reparto de la tarifa con la que se cobró. Cambiar hoy el
`porcentaje_conductor` no reescribe lo ya ganado, y eso es deliberado: el dinero
que alguien ya se ganó no se recalcula.

## Soporte

| Función | Parámetros | Devuelve | Quién |
|---|---|---|---|
| `abrir_ticket` | `p_asunto`, `p_mensaje`, `p_categoria`, `p_viaje_id` | `uuid` | cualquier usuario |
| `responder_ticket` | `p_ticket_id`, `p_respuesta`, `p_estado` | — | solo administración |

`p_estado` admite `abierto`, `en_proceso`, `resuelto` o `cerrado`; cualquier otro
valor rebota con `check_violation`. El autor de un caso no puede editarlo: si
pudiera, cambiaría el asunto después de que le respondieran y dejaría la
respuesta sin sentido.

## Administración

| Función | Parámetros | Devuelve |
|---|---|---|
| `revisar_documento` | `p_documento_id`, `p_aprobado` | — |
| `revisar_conductor` | `p_conductor_id`, `p_aprobado` | el estado resultante |

`revisar_conductor` **vuelve a comprobar en el servidor** que estén los cuatro
documentos aprobados y que haya al menos un vehículo. Aprobar sin los papeles
completos rebota aunque se manipule el cliente.

## Direcciones

| Función | Parámetros | Devuelve |
|---|---|---|
| `recordar_direccion` | `p_direccion`, `p_lat`, `p_lng`, `p_etiqueta` | `uuid` |
| `limpiar_direcciones_viejas` | `p_conservar` (10 por defecto) | cuántas borró |

## Notificaciones

`marcar_notificaciones_leidas()` no lleva parámetros y devuelve cuántas marcó.
Las notificaciones **no las crea la app**: las escriben los triggers
`notificar_cambio_viaje()`, `notificar_revision_conductor()` y
`notificar_revision_documento()` cuando cambia lo que describen.
`crear_notificacion` existe, pero solo `service_role` puede ejecutarla: si el
cliente pudiera crear notificaciones, cualquiera podría escribirle a cualquiera.

## Tablas y vistas que la app lee directo

Todas con RLS activa. La app nunca filtra por usuario en la consulta —no haría
falta y no serviría de nada—: las políticas ya devuelven solo las filas que a
esa cuenta le tocan.

| Objeto | Qué es | Quién lee |
|---|---|---|
| `profiles` | perfiles | el propio, y los que el rol permita ver |
| `viajes_detalle` | vista de `viajes` con chofer, vehículo y categoría ya unidos | los participantes; la administración, todos |
| `conductores_revision` | vista con el chofer, sus vehículos y sus documentos | solo administración |
| `mensajes` | chat del viaje | los dos participantes |
| `codigos_viaje` | el código de seis dígitos | **solo el pasajero** |
| `notificaciones` | avisos | cada quien los suyos |
| `tickets_soporte` | casos | el autor; la administración, todos |
| `tarifas`, `categorias_vehiculo` | precios y tipos de vehículo | todos leen, solo administración escribe |
| `metodos_pago`, `direcciones_guardadas`, `lugares` | datos del pasajero | cada quien los suyos |
| `vehiculos`, `conductores`, `documentos_conductor` | datos del chofer | el chofer y la administración |
| `calificaciones`, `ubicaciones`, `pagos` | rastro de cada viaje | los participantes |

Las dos vistas son `security_invoker`, así que **arrastran la RLS de sus
tablas**. Sin eso una vista sería un agujero: leería con los permisos de quien la
creó y devolvería filas ajenas a cualquiera que la consultara.

`codigos_viaje` es una tabla aparte y no una columna de `viajes` por una razón
concreta: **RLS filtra filas, no columnas.** En una columna, el chofer podría
leer el código que tiene que pedirle al pasajero, y la verificación no
verificaría nada.

## Realtime

| Canal | Tabla | Evento | Filtro |
|---|---|---|---|
| `viajes-…` | `viajes` | todos | ninguno |
| `chat-<viaje>-…` | `mensajes` | `INSERT` | `viaje_id` |
| `notif-…` | `notificaciones` | `INSERT` | `usuario_id` |

Supabase solo emite las filas que RLS dejaría leer a esa sesión, así que un
pasajero no se entera de los viajes ajenos aunque el canal de `viajes` no lleve
filtro. Los filtros de chat y notificaciones son para que el evento ni siquiera
viaje, no para autorizar.

El evento trae la fila cruda de `viajes`, sin los datos del chofer ni del auto;
por eso al recibirlo la app reconsulta `viajes_detalle` en vez de pintar lo que
llegó.

Cada canal lleva un sufijo con la marca de tiempo en microsegundos para no
chocar con otro de la misma pantalla, y hay que cerrarlo con `cerrarCanal()` en
el `dispose`.

## Storage

| Bucket | Acceso | Cómo se lee |
|---|---|---|
| `avatares` | público | `getPublicUrl()` |
| `documentos` | privado | `createSignedUrl(ruta, 3600)` |

Los documentos de un chofer —los suyos y los de cada vehículo— no pueden ser
públicos: son documentos de identidad. Se abren con un enlace firmado que
caduca en una hora.

## Autenticación

La app usa el cliente de Supabase tal cual: `signUp`, `signInWithPassword`,
`resetPasswordForEmail`, `updateUser` y `signOut`, más `onAuthStateChange` para
restaurar la sesión al abrir.

Dos cosas las decide la base, no la app:

- `handle_new_user()` crea el perfil al registrarse. El registro público no
  puede elegir un rol administrativo.
- `prevent_role_self_edit()` impide que alguien se cambie el rol a sí mismo. Por
  eso el rol no aparece en la pantalla de configuración: no es que se oculte, es
  que el servidor lo rechazaría.

Para cambiar el correo o la contraseña, la app pide antes la contraseña actual y
la verifica con un `signInWithPassword` contra la sesión abierta.

## Permisos de ejecución

La regla, desde el 2026-09-02:

> **Ninguna función `security definer` es ejecutable por `anon`.** Todas tienen
> `EXECUTE` para `authenticated` y `service_role`, y nada más.

Eso no sustituye a la comprobación de dentro —cada función sigue empezando por
`auth.uid()` o `es_administrativo()`—, la respalda. Una sesión sin autenticar ni
siquiera llega a ejecutar el cuerpo.

Cinco funciones `security invoker` sí siguen abiertas a `anon`, y está bien que
lo estén: `cotizar_viaje` y `cotizar_categorias`, que solo calculan un precio, y
`es_superadmin`, `posicion_vigente_minutos` y `radio_busqueda_km`, que leen
configuración. Al ser `invoker` corren con los permisos de quien llama, así que
una sesión anónima que las use ve lo que RLS le deja ver a una sesión anónima:
nada de nadie.

Al escribir un `revoke`, hacerlo sobre `public` además de sobre el rol:

```sql
revoke execute on function public.lo_que_sea(uuid) from anon, public;
```

`anon` hereda de `public`. Si el permiso llegó por ahí, revocárselo solo a `anon`
no quita nada y deja la sensación de haberlo arreglado.

El estado de partida y los dos arreglos están en
[`infra/sql/2026-09-02-permisos-de-funciones.sql`](../infra/sql/2026-09-02-permisos-de-funciones.sql).

> **El linter de Supabase avisa de todas las `security definer` que puede llamar
> `authenticated`, y aquí son casi todas.** No es un hallazgo: es la forma del
> proyecto. La lógica vive en funciones `definer` justamente para que el cliente
> no pueda saltársela, y para llamarlas hay que estar autenticado. Comprobar que
> cada una valida por dentro sí importa; que el linter las liste, no.

## Lo que falta cerrar

- **La protección contra contraseñas filtradas está apagada.** Supabase Auth
  puede contrastar cada contraseña nueva con HaveIBeenPwned y rechazar las que
  ya se filtraron. Es un interruptor del panel, no código. Para una app donde
  la cuenta guarda viajes, dirección de casa y método de pago, vale la pena.
- **El cobro con DeUna está escrito pero no cobra todavía.** Falta desplegar la
  Edge Function con las credenciales de Payválida, y falta saber quién avisa de
  que el pasajero pagó: no hay webhook ni consulta de estado documentados. Las
  preguntas abiertas están en [`PAGOS.md`](PAGOS.md).
- **La tarjeta sigue sin pasarela.** `registrar_metodo_pago` acepta un token,
  pero no hay quién lo emita.
