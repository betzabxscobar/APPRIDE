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
//
// Al cancelar NO se corta el mes en marcha: ya esta pagado. Se deja correr
// `vigente_hasta` y el chofer se apaga solo cuando llega la fecha.
//
// Desplegar (cuando esten las credenciales):
//   supabase secrets set PAYPAL_CLIENT_ID=... PAYPAL_SECRET=... \
//                        PAYPAL_WEBHOOK_ID=... PAYPAL_ENTORNO=sandbox
//   supabase functions deploy webhook-paypal --no-verify-jwt
// y en el panel de PayPal, apuntar el webhook a:
//   https://<proyecto>.supabase.co/functions/v1/webhook-paypal
//
// Ver docs/CUOTA.md.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
  if (!r.ok) return null;
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

/// Un mes desde hoy, o desde donde iba si todavia le quedaba tiempo.
///
/// Renovar antes de que venza no puede regalar dias ni quitarlos: se encadena
/// al final del periodo que ya tenia pagado.
function nuevaVigencia(actual: string | null): string {
  const desde = actual && new Date(actual) > new Date()
    ? new Date(actual)
    : new Date();
  const hasta = new Date(desde);
  hasta.setMonth(hasta.getMonth() + 1);
  return hasta.toISOString();
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405);

  const clientId = Deno.env.get('PAYPAL_CLIENT_ID');
  const secreto = Deno.env.get('PAYPAL_SECRET');
  const webhookId = Deno.env.get('PAYPAL_WEBHOOK_ID');
  const base = ENTORNOS[Deno.env.get('PAYPAL_ENTORNO') ?? 'sandbox'];

  if (!clientId || !secreto || !webhookId) {
    return json({ error: 'El webhook de PayPal todavia no esta configurado' }, 503);
  }

  let evento: Record<string, unknown>;
  try {
    evento = await req.json();
  } catch {
    return json({ error: 'Cuerpo invalido' }, 400);
  }

  const acceso = await token(base, clientId, secreto);
  if (!acceso) return json({ error: 'No pudimos contactar con PayPal' }, 502);

  if (!await firmaValida(base, acceso, webhookId, req, evento)) {
    // 401 y no 400: esto es alguien intentando colarse, no un error de formato.
    return json({ error: 'Firma invalida' }, 401);
  }

  const tipo = String(evento.event_type ?? '');
  const recurso = (evento.resource ?? {}) as Record<string, unknown>;

  // En los eventos de suscripcion la referencia es `resource.id`; en el cobro
  // recurrente (`PAYMENT.SALE.COMPLETED`) viene en `billing_agreement_id`.
  const referencia = String(
    recurso.billing_agreement_id ?? recurso.id ?? '',
  );
  if (!referencia) return json({ ok: true, ignorado: 'sin referencia' });

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: fila } = await db
    .from('suscripciones_chofer')
    .select('id, conductor_id, vigente_hasta')
    .eq('referencia_externa', referencia)
    .maybeSingle();

  // `custom_id` es el uuid del chofer que puso `suscripcion-paypal`. Se usa
  // cuando el evento llega antes de que se guardara la fila, que pasa.
  const conductor = fila?.conductor_id ?? (recurso.custom_id as string | undefined);
  if (!conductor) return json({ ok: true, ignorado: 'no sabemos de quien es' });

  const comun = {
    conductor_id: conductor,
    proveedor: 'paypal',
    referencia_externa: referencia,
    actualizado_en: new Date().toISOString(),
    datos: evento,
  };

  let cambio: Record<string, unknown>;
  switch (tipo) {
    case 'BILLING.SUBSCRIPTION.ACTIVATED':
    case 'PAYMENT.SALE.COMPLETED':
      cambio = {
        ...comun,
        estado: 'activa',
        vigente_hasta: nuevaVigencia(fila?.vigente_hasta ?? null),
        monto: 15,
        moneda: 'USD',
      };
      break;

    case 'BILLING.SUBSCRIPTION.CANCELLED':
    case 'BILLING.SUBSCRIPTION.SUSPENDED':
      // El mes que ya pago se respeta: se marca cancelada pero `vigente_hasta`
      // no se toca. Deja de recibir viajes cuando llegue esa fecha, no antes.
      cambio = { ...comun, estado: 'cancelada' };
      break;

    case 'BILLING.SUBSCRIPTION.EXPIRED':
      cambio = { ...comun, estado: 'vencida' };
      break;

    default:
      // PayPal manda muchos eventos que aqui no importan. Se responde 200 para
      // que no los reintente eternamente.
      return json({ ok: true, ignorado: tipo });
  }

  const { error } = await db
    .from('suscripciones_chofer')
    .upsert(cambio, { onConflict: 'referencia_externa' });

  if (error) {
    // 500 a proposito: PayPal reintenta, y es lo que se quiere si la base
    // fallo un momento. El `upsert` sobre `referencia_externa` hace que el
    // reintento no duplique nada.
    return json({ error: error.message }, 500);
  }

  return json({ ok: true, evento: tipo });
});
