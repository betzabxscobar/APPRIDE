# Cobrar un viaje

Ride cobra en efectivo desde el primer día. La transferencia es el segundo
método: el pasajero copia el número de cuenta del chofer, transfiere desde la
app de su banco y adjunta el comprobante.

> Esto es lo que **el pasajero paga por su viaje**. Lo que **el chofer paga por
> usar la app** —15 USD al mes, con PayPal— es otro circuito y está en
> [`CUOTA.md`](CUOTA.md).

## Ride no toca ese dinero

Es lo primero que hay que entender, y por eso está escrito en la propia
pantalla y no en una nota al pie: **la app enseña el número de cuenta, nada
más**. La transferencia la hace el pasajero desde su banco a la cuenta del
chofer. Ride no es intermediario, no retiene el importe y no puede devolverlo.

Eso cambia quién responde si el dinero no llega, y el pasajero tiene que
saberlo antes de transferir.

## La pregunta difícil: ¿cómo se sabe que pagó?

Con efectivo es fácil: el chofer tiene los billetes en la mano. Con una
transferencia hay que esperar a que aparezca en el banco, y **el único que
puede verlo es el chofer**. No hay integración bancaria que lo diga.

Así que la comprobación son dos pasos y dos personas:

| # | Quién | Qué hace | Función |
|---|---|---|---|
| 1 | Pasajero | Transfiere, adjunta el comprobante y avisa | `reportar_transferencia()` |
| 2 | Chofer | Mira su banco, contrasta y confirma | `confirmar_pago_recibido()` |

**El comprobante no es la prueba de que el dinero llegó.** Una transferencia se
puede reversar y una captura se puede trucar. El comprobante sirve para otra
cosa: para que el chofer sepa qué buscar, y para que quede algo guardado si más
tarde hay una discusión. Quien decide sigue siendo el chofer mirando su cuenta.

Por eso el paso 1 **no** marca el cobro como completado. Solo pone
`reportado_en` y avisa al chofer.

## El viaje no se cierra hasta que el cobro esté confirmado

`finalizar_viaje()` rebota si el método es transferencia y el pago sigue
pendiente:

> Confirma que te llego la transferencia para poder cerrar el viaje

Es la única forma de cobro donde el chofer no tiene el dinero delante al
terminar. Si se dejara cerrar antes, el pasajero se baja y el cobro se queda
colgado sin nadie a quien reclamar.

### Eso obligó a mover el cobro

Hasta ahora el cobro nacía **dentro** de `finalizar_viaje`, o sea que no existía
hasta el final. Si el cierre depende del cobro y el cobro del cierre, no arranca
ninguno de los dos.

Ahora, cuando el método es transferencia, el cobro nace al pasar el viaje a
`EN_CURSO` (`abrir_cobro_si_es_transferencia()`, llamada desde
`avanzar_viaje()`). El pasajero puede ir pagando por el camino y al llegar solo
queda confirmar. Con efectivo y tarjeta el cobro sigue naciendo al final, como
siempre.

En la app, el botón «Pagar por transferencia» sale durante el viaje por el mismo
motivo: esperar al cierre dejaría a los dos bloqueados.

## El comprobante

Vive en el depósito `comprobantes` de Supabase Storage, **privado**: un
comprobante lleva número de cuenta, nombre y monto.

- Cada pasajero escribe solo en su carpeta (`<uuid>/<viaje>.jpg`).
- Lo leen tres: quien lo subió, el chofer de ese viaje y la administración.
- Se sirve con enlace firmado de una hora, no con URL pública.
- Máximo 5 MB, y **solo imágenes**: el chofer lo ve con `Image.network`, y un
  PDF ahí no se pinta. Las dos apps lo suben ya reducido a 1600 px de ancho.

Se puede volver a subir: si la primera foto salió movida, la segunda pisa a la
primera en vez de acumular basura.

## Quién puede hacer qué

- **La app no marca nada como cobrado.** `confirmar_pago_recibido()` comprueba
  con `auth.uid()` que ese viaje es del chofer que llama.
- **El pasajero no confirma su propio pago.** Solo puede reportar, y reportar no
  cierra el cobro.
- **El importe no viaja desde el teléfono.** Lo pone Postgres al abrir el cobro,
  leyendo la tarifa del viaje.

Confirmar dos veces no abona dos veces: el índice único
`movimientos_chofer_viaje_tipo_unico` lo impide y la función sale antes de tocar
el saldo.

## La comisión

Al confirmar el cobro, la comisión de la app pasa al saldo del chofer como un
movimiento negativo, igual que con el efectivo: cobró él, así que queda
debiéndole a Ride su parte. El reparto sale del porcentaje que tenía **su**
tarifa, no del de hoy. Ver
[`2026-09-02-billetera-del-chofer.sql`](../infra/sql/2026-09-02-billetera-del-chofer.sql).

## Qué se retiró

**DeUna ya no está.** Se cobraba con un QR de Payválida y llevaba meses
esperando credenciales que no llegaron, con dos preguntas abiertas que nunca se
respondieron: cómo lleva el QR el importe y quién avisa de que el pasajero pagó.
La transferencia resuelve lo mismo sin depender de nadie, y el comprobante
cubre la segunda pregunta.

Se fueron con ello `cobro_deuna()`, `confirmar_cobro_deuna()`, la Edge Function
`cobro-deuna` y la pantalla del QR. El tipo de método `deuna` pasó a
`transferencia` en las cuentas que ya lo tenían.

## La tarjeta sigue sin pasarela

`registrar_metodo_pago` acepta un token, pero no hay quién lo emita. **La app
nunca pide ni almacena un número de tarjeta**: la función de la base rechaza
cualquier valor con forma de PAN, y en la app no hay formulario donde
escribirlo.

## Revisar cobros a mano

Lo que está pendiente de cobrar:

```sql
select v.id, p.monto, p.estado, p.reportado_en,
       p.comprobante_url is not null as tiene_comprobante,
       coalesce(m.tipo, 'efectivo') as metodo
from public.pagos p
join public.viajes v on v.id = p.viaje_id
left join public.metodos_pago m on m.id = p.metodo_pago_id
where p.tipo = 'pago' and p.estado = 'pendiente'
order by p.fecha desc;
```

Los que el pasajero dice haber pagado y el chofer todavía no confirma:

```sql
select viaje_id, monto, reportado_en, comprobante_url
from public.pagos
where estado = 'pendiente' and reportado_en is not null
order by reportado_en;
```
