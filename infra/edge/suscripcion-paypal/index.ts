// Edge Function `suscripcion-paypal` — abre la suscripcion mensual del chofer
// ---------------------------------------------------------------------------
// El chofer paga 15 USD al mes para poder recibir viajes. Esta funcion crea la
// suscripcion en PayPal y devuelve el enlace donde el chofer la aprueba.
//
// Existe porque el `client_secret` de PayPal no puede vivir en el APK: se
// descompila en diez minutos. Aqui es una variable de entorno del proyecto.
//
// Lo que NO hace, a proposito:
//   - No marca a nadie como pagado. Crear la suscripcion no es haber cobrado.
//     Eso lo hace `webhook-paypal` cuando PayPal confirma el cobro.
//   - No recibe el importe ni el plan desde el telefono. Si el cliente pudiera
//     mandar el precio, cualquiera pagaria un centavo al mes.
//
// El enlace de pago suelto que se uso al principio
// (paypal.com/ncp/payment/UXEAEF8N82RWU) NO sirve para esto: es un cobro unico,
// igual para todos, sin forma de saber quien pago ni de renovar solo. Aqui se
// usa la API de suscripciones, que sí manda `custom_id` con el uuid del chofer.
//
// Desplegar (con las credenciales Live; `sandbox` solo para probar):
//   supabase secrets set PAYPAL_CLIENT_ID=... PAYPAL_SECRET=... \
//                        PAYPAL_PLAN_ID=P-... PAYPAL_ENTORNO=produccion
//   supabase functions deploy suscripcion-paypal
//
// Ver docs/CUOTA.md.

// Version exacta, la misma que usa la web: con `@2` cada despliegue podia traer
// una 2.x distinta sin que nadie la probara, justo en el codigo que cobra.
import { createClient } from 'npm:@supabase/supabase-js@2.112.4';

// Las webs a las que se puede volver despues de aprobar el pago. La app no manda
// nada y vuelve por `ride://`. Lista fija a proposito: aceptar cualquier URL del
// cliente convertiria esta funcion en un redireccionador abierto. El servidor
// de desarrollo solo vale mientras se prueba contra sandbox.
const WEBS = [
  'https://rideviajes.com.ec/',
  'https://www.rideviajes.com.ec/',
  'https://betzabxscobar.github.io/WEB-RIDE/',
];
const WEBS_DE_PRUEBA = ['http://localhost:5173/'];

const ENTORNOS: Record<string, string> = {
  sandbox: 'https://api-m.sandbox.paypal.com',
  produccion: 'https://api-m.paypal.com',
};

// `apikey` y `x-client-info` las manda supabase-js en toda peticion; si no
// estan aqui, el navegador aprueba el preflight y luego bloquea el POST sin
// decir nada util. Se vio desde la web: en los registros solo llegaban OPTIONS
// y ni un POST. Desde la app no se notaba porque Flutter no pasa por CORS.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/// Token de aplicacion de PayPal. Dura horas, pero se pide uno por llamada:
/// cachearlo en memoria no sirve de nada porque cada invocacion de una Edge
/// Function puede caer en una instancia distinta.
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405);

  // `.trim()` en todas: el campo de secretos de Supabase es multilinea y al
  // pegar se cuela un salto de linea con facilidad. Uno al final del secreto
  // rompe el Basic auth y PayPal responde `invalid_client`, que se lee igual
  // que un secreto equivocado y manda a buscar donde no es.
  const clientId = Deno.env.get('PAYPAL_CLIENT_ID')?.trim();
  const secreto = Deno.env.get('PAYPAL_SECRET')?.trim();
  const plan = Deno.env.get('PAYPAL_PLAN_ID')?.trim();
  const entorno = Deno.env.get('PAYPAL_ENTORNO')?.trim() ?? 'sandbox';
  const base = ENTORNOS[entorno];

  if (!clientId || !secreto || !plan) {
    // Sin credenciales no se inventa nada: se dice que falta configurarlas.
    return json({ error: 'El cobro con PayPal todavia no esta configurado' }, 503);
  }
  if (!base) {
    return json({ error: `PAYPAL_ENTORNO no vale: "${entorno}"` }, 503);
  }

  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return json({ error: 'Debes iniciar sesion' }, 401);

  // Con el JWT de quien llama, para saber QUIEN es. El uuid no se acepta del
  // cuerpo de la peticion: si viniera de ahi, un chofer podria pagarle la
  // cuota a otro, o peor, decir que la suscripcion que va a crear es de otro.
  const comoChofer = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: autorizacion } } },
  );

  const { data: sesion } = await comoChofer.auth.getUser();
  const uid = sesion?.user?.id;
  if (!uid) return json({ error: 'Debes iniciar sesion' }, 401);

  // Que sea chofer de verdad. Un pasajero no tiene por que abrir suscripciones.
  const { data: conductor } = await comoChofer
    .from('conductores')
    .select('id')
    .eq('id', uid)
    .maybeSingle();
  if (!conductor) {
    return json({ error: 'Solo un chofer paga la cuota mensual' }, 403);
  }

  // Al que ya pago y le quedan dias no se le abre otra: pagaria dos cuotas al
  // mes. La pantalla ya lo evita, pero la funcion se puede llamar directo.
  const { data: pagada } = await comoChofer
    .from('suscripciones_chofer')
    .select('vigente_hasta')
    .eq('conductor_id', uid)
    .eq('proveedor', 'paypal')
    .eq('estado', 'activa')
    .gt('vigente_hasta', new Date().toISOString())
    .limit(1)
    .maybeSingle();
  if (pagada) {
    return json({ error: 'Tu cuota ya esta pagada y se renueva sola cada mes.' }, 409);
  }

  // Desde la web, volver a `ride://` deja al chofer ante un error del navegador.
  const peticion = await req.json().catch(() => ({})) as { vuelta?: unknown };
  const pedida = typeof peticion.vuelta === 'string' ? peticion.vuelta : '';
  const permitidas = entorno === 'produccion' ? WEBS : [...WEBS, ...WEBS_DE_PRUEBA];
  const vuelta = permitidas.some((w) => pedida.startsWith(w)) ? pedida : null;

  const acceso = await token(base, clientId, secreto);
  if (!acceso) return json({ error: 'No pudimos contactar con PayPal' }, 502);

  // Si ya dejo una abierta y sin aprobar, se le devuelve ESA en vez de crear
  // otra. Evita que dos toques al boton abran dos suscripciones y que el chofer
  // termine pagando 30 al mes.
  //
  // Antes esto se hacia con un `PayPal-Request-Id` fijo por chofer, que PayPal
  // trata como clave de idempotencia: el problema es que entonces el que
  // cancelaba su suscripcion se quedaba sin poder abrir otra nunca, porque
  // PayPal seguia devolviendo la vieja. Preguntando por el estado real se
  // reutiliza solo lo que de verdad sigue esperando aprobacion.
  const { data: abierta } = await comoChofer
    .from('suscripciones_chofer')
    .select('referencia_externa')
    .eq('conductor_id', uid)
    .eq('estado', 'pendiente')
    .not('referencia_externa', 'is', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (abierta?.referencia_externa) {
    const r = await fetch(
      `${base}/v1/billing/subscriptions/${abierta.referencia_externa}`,
      { headers: { Authorization: `Bearer ${acceso}` } },
    );
    if (r.ok) {
      const previa = await r.json().catch(() => null);
      if (previa?.status === 'APPROVAL_PENDING') {
        const enlace = (previa.links ?? [])
          .find((l: { rel: string }) => l.rel === 'approve')?.href;
        if (enlace) {
          return json({ suscripcion_id: previa.id, aprobar_en: enlace });
        }
      }
    }
  }

  const r = await fetch(`${base}/v1/billing/subscriptions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acceso}`,
      'Content-Type': 'application/json',
      // Unico por intento. Protege del doble toque dentro de la misma
      // pulsacion, pero sin dejar al chofer atado a una suscripcion vieja: de
      // reutilizar la que sigue abierta se encarga la consulta de arriba.
      'PayPal-Request-Id': `ride-cuota-${uid}-${Date.now()}`,
    },
    body: JSON.stringify({
      plan_id: plan,
      // La pieza clave: es lo unico que vuelve en el webhook y permite saber
      // de que chofer es el cobro. Sin esto no hay forma de activar a nadie.
      custom_id: uid,
      application_context: {
        brand_name: 'Ride',
        locale: 'es-EC',
        user_action: 'SUBSCRIBE_NOW',
        // A donde vuelve el navegador. Son deeplinks de la app; si no estan
        // registrados, PayPal igual cobra: quien activa es el webhook, no esta
        // vuelta. Por eso no se usa la vuelta para dar por pagado nada.
        return_url: vuelta ?? 'ride://suscripcion/ok',
        cancel_url: vuelta ?? 'ride://suscripcion/cancelada',
      },
    }),
  });

  const cuerpo = await r.json().catch(() => null);
  if (!r.ok || !cuerpo?.id) {
    return json({
      error: cuerpo?.message ?? 'PayPal rechazo la suscripcion',
    }, 502);
  }

  const aprobar = (cuerpo.links ?? [])
    .find((l: { rel: string }) => l.rel === 'approve')?.href;

  // Queda constancia de que se abrio, en estado `pendiente`. Todavia no vale
  // para trabajar: `suscripcion_vigente()` solo mira las `activa`.
  const comoServicio = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  await comoServicio.from('suscripciones_chofer').upsert({
    conductor_id: uid,
    estado: 'pendiente',
    proveedor: 'paypal',
    referencia_externa: cuerpo.id,
    datos: { abierta_en: new Date().toISOString(), status: cuerpo.status },
  }, { onConflict: 'referencia_externa' });

  return json({ suscripcion_id: cuerpo.id, aprobar_en: aprobar });
});
