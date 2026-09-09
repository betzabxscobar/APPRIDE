# La cuota mensual del chofer

Un chofer paga **15 USD al mes** para poder recibir viajes. Sin la cuota al día
entra a la app, ve su perfil, su historial y sus ganancias, pero no se puede
poner en línea ni aceptar nada.

Cobra PayPal, con una suscripción que se renueva sola. Este documento cuenta qué
está construido, dónde está el corte y qué falta para cobrar de verdad.

## Qué está hecho

| Pieza | Dónde | Estado |
|---|---|---|
| Tabla `suscripciones_chofer` | [`2026-09-09-suscripcion-del-chofer.sql`](../infra/sql/2026-09-09-suscripcion-del-chofer.sql) | aplicado |
| `suscripcion_vigente()` — ¿puede trabajar hoy? | mismo archivo | aplicado |
| `mi_suscripcion()` — lo que pinta el panel | mismo archivo | aplicado |
| Las tres puertas del corte | mismo archivo | aplicado y probado |
| Mes de cortesía a los que ya estaban | mismo archivo | aplicado |
| Edge Function `suscripcion-paypal` — abre la suscripción | [`infra/edge/suscripcion-paypal/`](../infra/edge/suscripcion-paypal/index.ts) | escrita, **sin desplegar** |
| Edge Function `webhook-paypal` — la activa al cobrar | [`infra/edge/webhook-paypal/`](../infra/edge/webhook-paypal/index.ts) | escrita, **sin desplegar** |
| Panel del chofer | `lib/screens/driver/subscription_screen.dart` | hecho |

Falta una sola cosa para cobrar: **las credenciales REST de PayPal y un plan de
suscripción creado allí**. Todo lo demás está escrito y probado.

## Dónde está el corte

En Postgres, no en la app. Un APK se descompila en diez minutos y el teléfono
habla con PostgREST directamente, así que parchear la pantalla no sirve de nada.
Son tres puertas y las tres preguntan por la cuota:

| # | Puerta | Qué la protege |
|---|---|---|
| 1 | Ponerse `disponible` | trigger `conductor_disponible_con_cuota` |
| 2 | Ver solicitudes abiertas | `solicitudes_abiertas()` devuelve vacío |
| 3 | **Aceptar un viaje** | `aceptar_viaje()` lanza `conductor_sin_suscripcion` |

La 3 es la que de verdad protege el dinero: aunque alguien se salte las otras
dos y llame a `aceptar_viaje` a mano con el id de un viaje, ahí se queda. Las
otras dos existen para que el chofer se entere **antes** y no después de haber
intentado tomar un viaje.

### La puerta 1 tiene dos comportamientos, a propósito

- **Intenta encenderse sin cuota** → excepción, y la app le dice por qué.
- **Ya estaba en línea y se le vence** → no hay excepción: se le baja el
  interruptor y deja de recibir viajes.

El segundo caso es el que se escapó en la primera versión. Mirar solo la
transición apagado→encendido dejaba trabajando para siempre al que ya estaba en
línea cuando venció. Y no puede lanzar excepción porque el único `update` que
llega en ese caso es el reporte de posición, que corre cada 30 segundos:
reventarlo dejaría al chofer sin poder ni actualizarse.

### Cómo se comprobó

Con un rol `authenticated` de verdad y el `sub` del chofer en el JWT, no como
`postgres` —que ignora el RLS y da todo por bueno—. Cada prueba dentro de una
transacción que termina en `rollback`:

| Prueba | Resultado |
|---|---|
| Encenderse sin cuota | rebotado: `conductor_sin_suscripcion` |
| Ya en línea y le vence | `disponible` pasa solo a `false` |
| Ver solicitudes sin cuota | 0 visibles |
| Aceptar viaje sin cuota | rebotado: `conductor_sin_suscripcion` |
| Aceptar viaje con la cuota al día | pasa el filtro |

Los superadministradores se saltan el cobro: son cuentas internas y necesitan
poder probar el flujo de chofer (CU-A26).

## Cómo funciona el cobro

1. El chofer abre «Mi cuota mensual» y pulsa pagar.
2. La app llama a `suscripcion-paypal`. **No manda ni el importe ni el plan**:
   los pone la Edge Function desde sus variables de entorno. Si el teléfono
   pudiera decir el precio, cualquiera pagaría un centavo al mes.
3. La función crea la suscripción en PayPal con `custom_id` = el uuid del
   chofer, sacado del JWT y nunca del cuerpo de la petición. Guarda la fila en
   `pendiente`, que todavía no sirve para trabajar.
4. La app abre en el navegador el enlace donde el chofer aprueba el cobro.
5. PayPal cobra y avisa a `webhook-paypal`, que verifica la firma contra la API
   de PayPal y marca la suscripción `activa` con un mes de vigencia.
6. Cada mes PayPal vuelve a cobrar y a avisar (`PAYMENT.SALE.COMPLETED`), y la
   vigencia se encadena al final del periodo que ya tenía pagado.

**Volver de PayPal no activa nada.** El `return_url` es solo la vuelta del
navegador; quien da la cuota por pagada es el webhook. Por eso el panel ofrece
«Ya pagué» en vez de darlo por hecho: PayPal tarda unos segundos en avisar.

### Lo que la app no puede hacer

- **No marca su propia cuota como pagada.** `suscripciones_chofer` tiene RLS con
  política de `select` y ninguna de `insert` ni de `update`, así que la única
  que escribe es la `service_role`, que vive en el webhook.
- **No abre la suscripción de otro chofer.** El uuid sale de `auth.uid()`.
- **No se fía de su propia caché.** Si la consulta falla, `DriverSubscription`
  cae en `sinPagar()`: enseña el panel de cobro de más antes que regalar viajes.

### Al cancelar no se corta el mes en marcha

`BILLING.SUBSCRIPTION.CANCELLED` marca la fila como cancelada pero **no toca
`vigente_hasta`**: ese mes ya está pagado. El chofer deja de recibir viajes
cuando llega la fecha, no antes.

## El enlace de pago suelto no sirve para esto

El primer enlace que se manejó fue
`paypal.com/ncp/payment/UXEAEF8N82RWU`, un PayPal No-Code Checkout de 15 USD.
Está bien para cobrar una vez, pero no vale como cuota mensual:

- **Es un pago único**, no una suscripción: nadie renueva solo.
- **Es idéntico para todos los choferes** y no admite un identificador, así que
  al recibir el dinero no hay forma de saber de quién es.
- **No avisa a la app.** Sin webhook no hay nada que active a nadie.

Por eso se usa la API de suscripciones, que sí manda `custom_id` de vuelta en
cada evento.

## El mes de cortesía

Los choferes que ya estaban cuando se activó el cobro tienen un mes regalado,
con `proveedor = 'cortesia'` y `monto = 0`. Si no, se habrían quedado sin poder
salir a la calle de un día para otro. El `insert` lleva `on conflict do nothing`
sobre el índice de «una sola activa», así que volver a correr la migración no
regala otro mes.

En el panel se ve como «Mes de cortesía», con la opción de pagar por adelantado.

## Desplegar, cuando lleguen las credenciales

En el panel de PayPal hay que crear antes un **producto** y un **plan** de
suscripción mensual de 15 USD; el plan da un id `P-…`. Después:

```bash
supabase secrets set PAYPAL_CLIENT_ID=... PAYPAL_SECRET=... \
                     PAYPAL_PLAN_ID=P-... PAYPAL_WEBHOOK_ID=... \
                     PAYPAL_ENTORNO=sandbox
supabase functions deploy suscripcion-paypal
supabase functions deploy webhook-paypal --no-verify-jwt
```

Y en el panel de PayPal, apuntar el webhook a:

```
https://<proyecto>.supabase.co/functions/v1/webhook-paypal
```

suscrito a estos eventos: `BILLING.SUBSCRIPTION.ACTIVATED`,
`PAYMENT.SALE.COMPLETED`, `BILLING.SUBSCRIPTION.CANCELLED`,
`BILLING.SUBSCRIPTION.SUSPENDED` y `BILLING.SUBSCRIPTION.EXPIRED`.

`PAYPAL_ENTORNO` acepta `sandbox` o `produccion`. Sin credenciales las dos
funciones responden 503 y la app lo cuenta como «el cobro con PayPal todavía no
está configurado», que es la verdad y no un error raro.

> **`webhook-paypal` se despliega con `--no-verify-jwt`.** Quien llama es
> PayPal, que no tiene un token de Supabase. Eso deja la URL abierta a internet,
> así que lo primero que hace la función es pedirle a PayPal que confirme la
> firma del evento. Sin esa comprobación, cualquiera con la URL se regala meses
> gratis mandando un JSON. **El `PAYPAL_SECRET` no entra en el repositorio.**

## Dar cuota a mano

Mientras no haya credenciales —o para un caso de soporte— se puede activar desde
el SQL editor:

```sql
insert into public.suscripciones_chofer
  (conductor_id, estado, vigente_hasta, proveedor, monto, datos)
values
  ('<uuid del chofer>', 'activa', now() + interval '1 month', 'cortesia', 0,
   jsonb_build_object('motivo', 'por que se le regalo'));
```

Para ver quién está al día y a quién se le acaba:

```sql
select p.nombre, s.estado, s.proveedor, s.vigente_hasta::date,
       public.suscripcion_vigente(s.conductor_id) as puede_trabajar
from public.suscripciones_chofer s
join public.profiles p on p.id = s.conductor_id
order by s.vigente_hasta;
```
