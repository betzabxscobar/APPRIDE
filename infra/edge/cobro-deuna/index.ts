// Edge Function `cobro-deuna` — pide a Payvalida el QR de un viaje
// ---------------------------------------------------------------------------
// Existe por una sola razon: el `fixedhash` con el que se firma cada peticion
// es confidencial y la propia documentacion de Payvalida prohibe exponerlo en
// el frontend. Un APK se descompila en diez minutos, asi que la firma se hace
// aqui, donde el secreto es una variable de entorno del proyecto.
//
// Lo que NO hace, a proposito:
//   - No recibe el monto. Lo pone `cobro_deuna()` leyendo `pagos`. Si el
//     telefono pudiera mandar el importe, cualquiera pagaria 0,01 su viaje.
//   - No marca nada como pagado. Pedir el QR no es haber cobrado. Eso lo hace
//     `confirmar_cobro_deuna()`, y solo con la service_role.
//
// Desplegar (cuando lleguen las credenciales):
//   supabase secrets set DEUNA_MERCHANT=... DEUNA_FIXEDHASH=... DEUNA_ENTORNO=sandbox
//   supabase functions deploy cobro-deuna
//
// Ver docs/PAGOS.md.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ENTORNOS: Record<string, string> = {
  sandbox: 'https://api-test.payvalida.com/api/v4/merchants/qr/deuna',
  produccion: 'https://api.payvalida.com/api/v4/merchants/qr/deuna',
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/// SHA-512 en hexadecimal de `merchant + order + timestamp + fixedhash`, que es
/// exactamente el orden que pide la documentacion. Concatenacion sin separador:
/// cambiarlo por comas o guiones da una firma que Payvalida rechaza.
async function checksum(texto: string): Promise<string> {
  const bytes = new TextEncoder().encode(texto);
  const hash = await crypto.subtle.digest('SHA-512', bytes);
  return [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405);

  const merchant = Deno.env.get('DEUNA_MERCHANT');
  const fixedhash = Deno.env.get('DEUNA_FIXEDHASH');
  const url = Deno.env.get('DEUNA_URL') ??
    ENTORNOS[Deno.env.get('DEUNA_ENTORNO') ?? 'sandbox'];

  if (!merchant || !fixedhash || !url) {
    // Sin credenciales no se inventa nada: se dice que falta configurarlas.
    return json({ error: 'El cobro con DeUna todavia no esta configurado' }, 503);
  }

  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return json({ error: 'Debes iniciar sesion' }, 401);

  let viajeId: string | undefined;
  try {
    viajeId = (await req.json())?.viaje_id;
  } catch {
    return json({ error: 'Falta el viaje' }, 400);
  }
  if (!viajeId) return json({ error: 'Falta el viaje' }, 400);

  // Con el JWT de quien llama: `cobro_deuna` resuelve con `auth.uid()` si ese
  // viaje es suyo. Aqui no se comprueba nada de eso, y es lo correcto.
  const comoPasajero = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: autorizacion } } },
  );

  const { data, error } = await comoPasajero.rpc('cobro_deuna', {
    p_viaje_id: viajeId,
  });

  if (error) return json({ error: error.message }, 403);

  const cobro = Array.isArray(data) ? data[0] : data;
  if (!cobro) return json({ error: 'Este viaje no tiene un cobro que pagar' }, 404);
  if (cobro.estado !== 'pendiente') {
    return json({ ya_pagado: cobro.estado === 'completado', estado: cobro.estado });
  }

  const timestamp = new Date().toISOString();
  const firma = await checksum(merchant + cobro.orden + timestamp + fixedhash);

  const peticion = new URL(url);
  peticion.searchParams.set('merchant', merchant);
  peticion.searchParams.set('order', cobro.orden);
  peticion.searchParams.set('timestamp', timestamp);
  peticion.searchParams.set('checksum', firma);
  // TODO(credenciales): la documentacion publica no trae ningun parametro de
  // importe ni de moneda. Si Payvalida confirma que el QR lleva el monto, va
  // aqui —y sale de `cobro.monto`, nunca del cuerpo de la peticion—.

  let respuesta: Response;
  try {
    respuesta = await fetch(peticion, {
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    });
  } catch {
    return json({ error: 'No pudimos contactar con DeUna' }, 502);
  }

  const cuerpo = await respuesta.json().catch(() => null);
  if (!respuesta.ok || cuerpo?.CODE !== '0000') {
    return json({
      error: cuerpo?.DESC ?? 'DeUna rechazo el cobro',
      code: cuerpo?.CODE ?? String(respuesta.status),
    }, 502);
  }

  // Queda constancia de que se pidio el QR, con la hora y la firma exactas: el
  // dia que un cobro se discuta, hay que poder reconstruir la peticion. El QR
  // en base64 NO se guarda: son cientos de kilobytes por viaje y se puede
  // volver a pedir.
  const comoServicio = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  await comoServicio
    .from('pagos')
    .update({
      datos: {
        qr_pedido_en: timestamp,
        deep_link: cuerpo.DATA?.deepLink ?? null,
        code: cuerpo.CODE,
        entorno: url,
      },
      actualizado_en: new Date().toISOString(),
    })
    .eq('proveedor', 'deuna')
    .eq('referencia_externa', cobro.orden);

  return json({
    orden: cobro.orden,
    monto: cobro.monto,
    qr: cuerpo.DATA?.qr ?? null,
    deep_link: cuerpo.DATA?.deepLink ?? null,
  });
});
