# Cobrar un viaje con DeUna

Ride cobra en efectivo desde el primer día. DeUna es el segundo método: el
pasajero termina el viaje, ve un QR y paga desde su banco. Este documento cuenta
qué está construido, qué falta y qué hay que preguntarle a Payválida.

La integración es contra **Payválida**, que es quien expone la API de DeUna
(`docs.payvalida.com/api-deuna`). Toda su documentación pública son dos páginas:
una introducción y el método de creación de QR.

## Qué está hecho

| Pieza | Dónde | Estado |
|---|---|---|
| `deuna` como método de pago | [`2026-09-02-cobro-con-deuna.sql`](../infra/sql/2026-09-02-cobro-con-deuna.sql) | aplicado |
| `cobro_deuna()` — abre el cobro y fija la orden | mismo archivo | aplicado |
| `confirmar_cobro_deuna()` — marca el cobro y abona al chofer | mismo archivo | aplicado |
| Edge Function `cobro-deuna` — firma y pide el QR | [`infra/edge/cobro-deuna/`](../infra/edge/cobro-deuna/index.ts) | escrita, **sin desplegar** |
| `PaymentsService` y la pantalla del QR | `lib/services/payments_service.dart`, `lib/screens/payments/deuna_qr_screen.dart` | hecho |
| Quién avisa de que el pasajero pagó | — | **falta**, ver abajo |

Falta una sola cosa para cobrar de verdad, y son las credenciales: `merchant` y
`fixedhash`. Todo lo demás está escrito y probado.

## Cómo funciona el cobro

1. El chofer cierra el viaje. `finalizar_viaje()` inserta el pago en
   `pendiente`, porque el método del pasajero no es efectivo. **Nadie ha cobrado
   nada todavía**, y la base lo refleja.
2. El pasajero pulsa «Pagar con DeUna». La app llama a la Edge Function
   `cobro-deuna` con el id del viaje. **Nada más**: ni el importe ni la orden.
3. La Edge Function llama a `cobro_deuna()` con el JWT del pasajero. La base
   comprueba que ese viaje es suyo, devuelve el importe real y fija el número de
   orden (`pagos.referencia_externa`), que es siempre el mismo para ese viaje.
4. La Edge Function firma la petición con el `fixedhash` y le pide el QR a
   Payválida. El secreto no sale de ahí: la documentación de Payválida prohíbe
   expresamente exponerlo en el frontend, y un APK se descompila.
5. La app enseña el QR y el botón que abre la app de DeUna.
6. **Falta este paso**: alguien tiene que avisar de que el pasajero pagó. Cuando
   llegue ese aviso, quien lo reciba llama a `confirmar_cobro_deuna()`, que marca
   el pago como completado y abona al chofer su 85 %.

El paso 6 es el reverso exacto del efectivo. Al cobrar en efectivo el chofer se
queda el importe entero y queda debiéndole a la app su comisión; cobrando por
DeUna cobra la app y le queda debiendo al chofer su parte. El mismo saldo de
[`movimientos_chofer`](../infra/sql/2026-09-02-billetera-del-chofer.sql) sirve
para los dos casos, con el signo cambiado.

### Lo que la app no puede hacer

- **No manda el importe.** Lo pone `cobro_deuna()` leyendo `pagos`. Si el
  teléfono pudiera decir cuánto cuesta el viaje, cualquiera pagaría un centavo.
- **No marca nada como pagado.** `confirmar_cobro_deuna()` exige `service_role`
  o una cuenta administrativa; comprobado, un pasajero recibe `42501`.
- **No abre el cobro de un viaje ajeno.** `cobro_deuna()` resuelve el dueño con
  `auth.uid()`; comprobado también.

Confirmar dos veces la misma orden no abona dos veces: el índice único
`movimientos_chofer_viaje_tipo_unico` lo impide y la función sale antes de tocar
el saldo. Eso importa porque los avisos de pasarela se reintentan.

## Lo que dice la documentación de Payválida

Un solo método, `GET`:

- Producción: `https://api.payvalida.com/api/v4/merchants/qr/deuna`
- Sandbox: `https://api-test.payvalida.com/api/v4/merchants/qr/deuna`

Cuatro parámetros de consulta —`merchant`, `order`, `timestamp`, `checksum`—
donde el checksum es:

```
checksum = SHA512(merchant + order + timestamp + fixedhash)
```

Responde `CODE` `"0000"` con `DATA.qr` (PNG en base64, listo para un `<img>`) y
`DATA.deepLink` (abre la app de DeUna). Los errores documentados son dos: `0001`
cuerpo inválido y `0002` error interno.

## Lo que falta preguntar

Ordenado por lo que bloquea. Las tres primeras impiden cobrar; el resto se puede
resolver sobre la marcha.

1. **¿Cómo lleva el QR el importe?** La petición documentada no tiene ningún
   parámetro de monto ni de moneda. Si el QR no lo lleva, el pasajero escribe la
   cantidad que quiera y un viaje de 2,25 se paga con 0,25. Necesitamos saber si
   el importe va en un parámetro no documentado, si se registra antes con otro
   método, o si el QR es de importe abierto.
2. **¿Cómo nos enteramos de que pagó?** No hay webhook documentado ni endpoint
   para consultar el estado de una orden. Hace falta una de las dos:
   - un **webhook**: a qué URL lo mandan, qué trae el cuerpo, y con qué se
     verifica que viene de ellos (firma, IP, token);
   - o un **endpoint de consulta** por número de orden, para preguntar cada
     pocos segundos mientras el pasajero paga.
3. **Credenciales de sandbox**: `merchant` y `fixedhash` de prueba, y si hay
   forma de simular un pago sin dinero real.
4. **El `timestamp` se contradice consigo mismo.** La fórmula y el ejemplo usan
   ISO 8601 (`2025-06-09T15:29:35.437Z`); la tabla de parámetros dice «UNIX
   epoch». La Edge Function manda ISO 8601, como el ejemplo. Confirmar cuál.
5. **El checksum**: ¿hexadecimal en minúsculas? ¿La concatenación es sin ningún
   separador? Así está escrito y así se implementó, pero una firma mal formada
   solo devuelve `0001` y no dice por qué.
6. **¿Cuánto vive un QR, y se puede repetir la misma `order`?** Ride reutiliza
   la orden del viaje a propósito, para no cobrar dos veces. Si Payválida
   rechaza una orden repetida, hay que generar una nueva por intento.
7. **Devoluciones.** Un viaje que se cancela o se reclama después de pagado:
   ¿hay método, o se hace por su panel?
8. **Comisión y liquidación.** Cuánto se queda Payválida por transacción y en
   cuántos días llega el dinero. Afecta directo a la billetera del chofer: la
   app le abona su 85 % al confirmarse el cobro, antes de tener el dinero.
9. **Requisitos de alta**: si el comercio tiene que ser una empresa con RUC, y
   qué papeles piden. Ride es un proyecto académico.
10. **Límites por transacción**: mínimo y máximo. Un viaje de 1,40 es lo normal
    aquí; si el mínimo de DeUna es mayor, DeUna no sirve para viajes cortos.

## Desplegar, cuando lleguen las credenciales

```bash
supabase secrets set DEUNA_MERCHANT=... DEUNA_FIXEDHASH=... DEUNA_ENTORNO=sandbox
supabase functions deploy cobro-deuna
```

`DEUNA_ENTORNO` acepta `sandbox` o `produccion`; `DEUNA_URL` la pisa entera si
Payválida da otra dirección. Sin `DEUNA_MERCHANT` o sin `DEUNA_FIXEDHASH` la
función responde 503 y la app lo cuenta como «el cobro con DeUna todavía no está
configurado», que es la verdad y no un error raro.

**El `fixedhash` no entra en el repositorio.** Es la llave con la que se firma
cada cobro; vive en los secretos del proyecto Supabase y en ningún otro sitio.

## Conciliar a mano, mientras no haya aviso

Hasta que se resuelva la pregunta 2, un cobro se puede cerrar desde el SQL
editor —una cuenta administrativa también puede—:

```sql
select public.confirmar_cobro_deuna('ride7475f1328d724beeb93f41c4a0e0a348');
```

Marca el pago como completado y abona al chofer. Con `p_pagado => false` lo marca
fallido y no abona nada. Es idempotente: repetirlo no duplica el abono.

Para ver qué está pendiente de cobrar:

```sql
select p.referencia_externa, p.monto, p.fecha, v.pasajero_id
from public.pagos p join public.viajes v on v.id = p.viaje_id
where p.proveedor = 'deuna' and p.estado = 'pendiente'
order by p.fecha desc;
```
