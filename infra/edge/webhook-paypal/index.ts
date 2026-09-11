// Edge Function `webhook-paypal` — PayPal avisa de que un chofer pago
// ---------------------------------------------------------------------------
// Es la UNICA que activa una suscripcion. Ni la app ni el chofer pueden marcar
// su propia cuota como pagada: `suscripciones_chofer` tiene RLS sin politica de
// insert ni de update, asi que solo escribe la service_role, que vive aqui.
//
// Se despliega SIN `verify_jwt`, porque quien llama es PayPal y no tiene un
// token de Supabase. Eso deja la URL abierta a internet, asi que lo primero
// que hace es pedirle a PayPal que confirme la firma del evento. Sin esa
// comprobacion cualquiera con la URL se regala meses gratis mandando un JSON.
//
// Eventos que atiende:
//   BILLING.SUBSCRIPTION.ACTIVATED   el chofer aprobo la suscripcion
//   PAYMENT.SALE.COMPLETED           entro el cobro del mes (la renovacion)
//   BILLING.SUBSCRIPTION.CANCELLED   la dio de baja
//   BILLING.SUBSCRIPTION.SUSPENDED   PayPal la suspendio (tarjeta rechazada)
//   BILLING.SUBSCRIPTION.EXPIRED     se acabo
//   PAYMENT.SALE.REFUNDED            se devolvio un cobro: se quita su mes
//   PAYMENT.SALE.REVERSED            se revirtio un cobro (contracargo): igual
//
// Al cancelar NO se corta el mes en marcha: ya esta pagado. Se deja correr
// `vigente_hasta` y el chofer se apaga solo cuando llega la fecha.
//
// Activar y cobrar lo hace `aplicar_cobro_paypal()` en la base, en una sola
// transaccion. Antes era un `upsert` desde aqui, y chocaba con el indice que
// solo admite una cuota `activa` por chofer cuando el chofer tenia el mes de
// cortesia: 500, reintento de PayPal, otro 500... y el chofer pagaba sin que se
// le activara nada. Ver infra/sql/2026-09-11-cuota-paypal-con-cortesia.sql.
//
// Desplegar (con las credenciales Live; `sandbox` solo para probar):
//   supabase secrets set PAYPAL_CLIENT_ID=... PAYPAL_SECRET=... \
//                        PAYPAL_WEBHOOK_ID=... PAYPAL_ENTORNO=produccion
//   supabase functions deploy webhook-paypal --no-verify-jwt
// y en el panel de PayPal, apuntar el webhook a:
//   https://<proyecto>.supabase.co/functions/v1/webhook-paypal
//
// Ver docs/CUOTA.md.

// Version exacta, la misma que usa la web: con `@2` cada despliegue podia traer
// una 2.x distinta sin que nadie la probara, justo en el codigo que cobra.
import { createClient } from 'npm:@supabase/supabase-js@2.112.4';

const ENTORNOS: Record<string, string> = {
  sandbox: 'https://api-m.sandbox.paypal.com',
  produccion: 'https://api-m.paypal.com',
};

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function token(base: string, id: string, secreto: string): Promise<string | null> {
  const r = await fetch(`${base}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${id}:${secreto}`)}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  if (!r.ok) {
    // Al log, no a la respuesta: el que llama al webhook es cualquiera de
    // internet y no tiene por que enterarse de como estan las credenciales.
    // `invalid_client` casi siempre es una de dos: el secreto esta mal
    // copiado, o las credenciales son del otro entorno (las de sandbox no
    // valen en produccion ni al reves).
    const detalle = await r.text().catch(() => '');
    console.error(`PayPal /oauth2/token respondio ${r.status}: ${detalle}`);
    return null;
  }
  return (await r.json())?.access_token ?? null;
}

/// Le pregunta a PayPal si el evento lo mando el de verdad.
///
/// Se hace contra su API en vez de validar el certificado a mano: es lo que
/// recomienda su documentacion y evita tener que seguir la cadena de firmas.
async function firmaValida(
  base: string,
  acceso: string,
  webhookId: string,
  req: Request,
  evento: unknown,
): Promise<boolean> {
  const h = (n: string) => req.headers.get(n) ?? '';
  const r = await fetch(`${base}/v1/notifications/verify-webhook-signature`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${acceso}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      auth_algo: h('paypal-auth-algo'),
      cert_url: h('paypal-cert-url'),
      transmission_id: h('paypal-transmission-id'),
      transmission_sig: h('paypal-transmission-sig'),
      transmission_time: h('paypal-transmission-time'),
      webhook_id: webhookId,
      webhook_event: evento,
    }),
  });
  if (!r.ok) return false;
  return (await r.json())?.verification_status === 'SUCCESS';
}

/// La suscripcion a la que pertenece un cobro devuelto.
///
/// En `PAYMENT.SALE.REFUNDED` el recurso es el reembolso, que trae `sale_id`
/// pero no siempre `billing_agreement_id`: hay que preguntarle a PayPal por la
/// venta original para saber de que suscripcion era.
async function suscripcionDeLaVenta(
  base: string,
  acceso: string,
  ventaId: string,
): Promise<string | null> {
  const r = await fetch(`${base}/v1/payments/sale/${encodeURIComponent(ventaId)}`, {
    headers: { Authorization: `Bearer ${acceso}` },
  });
  if (!r.ok) {
    console.error(`PayPal /payments/sale/${ventaId} respondio ${r.status}`);
    return null;
  }
  return (await r.json())?.billing_agreement_id ?? null;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405);

  // `.trim()` en los tres: el campo de secretos de Supabase es multilinea y al
  // pegar se cuela un salto de linea con facilidad. Un salto al final del
  // secreto rompe el Basic auth y PayPal responde `invalid_client`, que se lee
  // igual que un secreto equivocado y manda a buscar donde no es.
  const clientId = Deno.env.get('PAYPAL_CLIENT_ID')?.trim();
  const secreto = Deno.env.get('PAYPAL_SECRET')?.trim();
  const webhookId = Deno.env.get('PAYPAL_WEBHOOK_ID')?.trim();
  const entorno = Deno.env.get('PAYPAL_ENTORNO')?.trim() ?? 'sandbox';
  const base = ENTORNOS[entorno];

  if (!clientId || !secreto || !webhookId) {
    return json({ error: 'El webhook de PayPal todavia no esta configurado' }, 503);
  }
  if (!base) {
    return json({ error: `PAYPAL_ENTORNO no vale: "${entorno}"` }, 503);
  }

  let evento: Record<string, unknown>;
  try {
    evento = await req.json();
  } catch {
    return json({ error: 'Cuerpo invalido' }, 400);
  }

  const acceso = await token(base, clientId, secreto);
  if (!acceso) {
    // Sin valores, solo su forma: sirve para ver de un vistazo si lo pegado
    // tiene la pinta que deberia y contra que entorno se esta hablando.
    //
    // Y se prueba el entorno contrario, porque `invalid_client` sale igual
    // cuando el secreto esta mal que cuando las credenciales son del otro
    // lado, y son dos arreglos distintos. Un par de sandbox y uno de
    // produccion se parecen: los dos empiezan por 'A' y miden ~80 caracteres,
    // asi que mirandolos no hay forma de saberlo.
    const otro = entorno === 'produccion' ? 'sandbox' : 'produccion';
    const valeEnElOtro = await token(ENTORNOS[otro], clientId, secreto);
    console.error(
      `entorno=${entorno} base=${base} ` +
      `client_id=${clientId.length} chars, empieza por "${clientId.slice(0, 4)}" ` +
      `secret=${secreto.length} chars` +
      (valeEnElOtro
        ? ` -> ESTAS CREDENCIALES SON DE ${otro.toUpperCase()}: cambia PAYPAL_ENTORNO a "${otro}", o saca otras de la pestana correcta.`
        : ' -> tampoco valen en el otro entorno: el client id y el secreto no son pareja, o el secreto esta mal copiado.'),
    );
    return json({ error: 'No pudimos contactar con PayPal' }, 502);
  }

  if (!await firmaValida(base, acceso, webhookId, req, evento)) {
    // 401 y no 400: esto es alguien intentando colarse, no un error de formato.
    return json({ error: 'Firma invalida' }, 401);
  }

  const tipo = String(evento.event_type ?? '');
  const recurso = (evento.resource ?? {}) as Record<string, unknown>;
  const esDevolucion = tipo === 'PAYMENT.SALE.REFUNDED' || tipo === 'PAYMENT.SALE.REVERSED';

  // En los eventos de suscripcion la referencia es `resource.id`; en los cobros
  // (`PAYMENT.SALE.*`) viene en `billing_agreement_id`. En un reembolso el
  // `resource.id` es el del reembolso, no el de la suscripcion: si no trae
  // `billing_agreement_id`, se busca por la venta original.
  let referencia = String(recurso.billing_agreement_id ?? '');
  if (!referencia && esDevolucion && recurso.sale_id) {
    referencia = await suscripcionDeLaVenta(base, acceso, String(recurso.sale_id)) ?? '';
  }
  if (!referencia && !esDevolucion) referencia = String(recurso.id ?? '');
  if (!referencia) return json({ ok: true, ignorado: 'sin referencia' });

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // PayPal entrega cada aviso «al menos una vez»: reintenta los que no confirma
  // a tiempo, y un reintento sumaba otro mes. El id del evento se apunta antes
  // de tocar nada; si ya estaba, este aviso ya se proceso.
  const eventoId = String(evento.id ?? '');
  if (eventoId) {
    const { error: yaVisto } = await db.from('eventos_paypal').insert({ id: eventoId, tipo });
    if (yaVisto?.code === '23505') return json({ ok: true, ignorado: 'repetido' });
    if (yaVisto) {
      console.error(`No se pudo apuntar el evento ${eventoId}: ${yaVisto.message}`);
      return json({ error: 'No pudimos procesar el aviso' }, 500);
    }
  }

  const { data: fila } = await db
    .from('suscripciones_chofer')
    .select('id, conductor_id, vigente_hasta')
    .eq('referencia_externa', referencia)
    .maybeSingle();

  // `custom_id` es el uuid del chofer que puso `suscripcion-paypal`. Se usa
  // cuando el evento llega antes de que se guardara la fila, que pasa. En los
  // cobros el mismo dato viaja como `custom`.
  const conductor = fila?.conductor_id ??
    (recurso.custom_id as string | undefined) ??
    (recurso.custom as string | undefined);
  if (!conductor) return json({ ok: true, ignorado: 'no sabemos de quien es' });

  let error: { message: string } | null = null;
  switch (tipo) {
    case 'BILLING.SUBSCRIPTION.ACTIVATED': {
      // Activar no es cobrar. PayPal manda el cobro del primer mes como un
      // PAYMENT.SALE.COMPLETED aparte: si esto tambien sumara un mes, cada chofer
      // recibiria dos por un pago. Sin fecha todavia no hay nada que activar
      // (la tabla exige fecha a una cuota `activa`); con fecha, es una
      // reactivacion y se respeta la que habia.
      if (!fila?.vigente_hasta) return json({ ok: true, esperando: 'el cobro' });
      ({ error } = await db.rpc('aplicar_cobro_paypal', {
        p_conductor: conductor,
        p_referencia: referencia,
        p_sumar_mes: false,
        p_monto: null,
        p_moneda: null,
        p_evento: evento,
      }));
      break;
    }

    case 'PAYMENT.SALE.COMPLETED': {
      const importe = (recurso.amount ?? {}) as { total?: string; currency?: string };
      ({ error } = await db.rpc('aplicar_cobro_paypal', {
        p_conductor: conductor,
        p_referencia: referencia,
        p_sumar_mes: true,
        p_monto: Number(importe.total ?? 15),
        p_moneda: importe.currency ?? 'USD',
        p_evento: evento,
      }));
      break;
    }

    case 'PAYMENT.SALE.REFUNDED':
    case 'PAYMENT.SALE.REVERSED':
      // Sin fila no hay mes que quitar: nunca se activo.
      if (!fila) return json({ ok: true, ignorado: 'devolucion de algo que no activamos' });
      ({ error } = await db.rpc('revertir_cobro_paypal', {
        p_referencia: referencia,
        p_evento: evento,
      }));
      break;

    case 'BILLING.SUBSCRIPTION.CANCELLED':
    case 'BILLING.SUBSCRIPTION.SUSPENDED':
    case 'BILLING.SUBSCRIPTION.EXPIRED':
      // El mes que ya pago se respeta: se marca cancelada pero `vigente_hasta`
      // no se toca. Deja de recibir viajes cuando llegue esa fecha, no antes.
      // Ninguno de estos estados es `activa`, asi que no choca con la cortesia.
      ({ error } = await db.from('suscripciones_chofer').upsert({
        conductor_id: conductor,
        proveedor: 'paypal',
        referencia_externa: referencia,
        estado: tipo === 'BILLING.SUBSCRIPTION.EXPIRED' ? 'vencida' : 'cancelada',
        actualizado_en: new Date().toISOString(),
        datos: evento,
      }, { onConflict: 'referencia_externa' }));
      break;

    default:
      // PayPal manda muchos eventos que aqui no importan. Se responde 200 para
      // que no los reintente eternamente.
      return json({ ok: true, ignorado: tipo });
  }

  if (error) {
    // 500 a proposito: PayPal reintenta, y es lo que se quiere si la base
    // fallo un momento. Se borra la marca del evento para que ese reintento se
    // procese. El detalle va al registro, no a quien llama: el webhook es publico.
    if (eventoId) await db.from('eventos_paypal').delete().eq('id', eventoId);
    console.error(`No se pudo guardar la suscripcion (${tipo}): ${error.message}`);
    return json({ error: 'No pudimos guardar el aviso' }, 500);
  }

  return json({ ok: true, evento: tipo });
});
