-- La cuota de PayPal se activa aunque el chofer tenga el mes de cortesia
-- ---------------------------------------------------------------------------
-- Segunda auditoria del 2026-09-11 (C3 y M7).
--
-- `suscripciones_chofer_una_activa` solo admite una fila `activa` por chofer, y
-- la cortesia es una fila `activa` aparte que nada cierra (no hay pg_cron: sigue
-- en `activa` aunque venza). Cuando llegaba el cobro, `webhook-paypal` ponia en
-- `activa` la fila de PayPal, el `upsert` chocaba con el indice (23505), el
-- webhook respondia 500 y PayPal reintentaba sin fin: el chofer pagaba y no se
-- activaba. Les pasaba a los cuatro choferes de hoy.
--
-- Ahora el webhook llama a estas funciones, que hacen todo en una transaccion:
-- cierran la otra fila activa y encadenan la vigencia. El mes pagado empieza
-- donde acaba lo que ya tenia (cortesia incluida), para no comerse dias.
--
-- Solo las llama la service_role desde la Edge Function.

create or replace function public.aplicar_cobro_paypal(
  p_conductor  uuid,
  p_referencia text,
  p_sumar_mes  boolean,
  p_monto      numeric,
  p_moneda     text,
  p_evento     jsonb
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_desde timestamptz;
  v_hasta timestamptz;
begin
  -- Un aviso a la vez por chofer: PayPal puede mandar la activacion y el cobro
  -- casi a la vez.
  perform 1 from public.conductores where id = p_conductor for update;
  if not found then
    raise exception 'No existe el chofer %', p_conductor using errcode = 'no_data_found';
  end if;

  if p_sumar_mes then
    -- `cancelada` tambien: quien cancelo y vuelve a suscribirse con dias
    -- pagados los conserva.
    select greatest(now(), coalesce(max(s.vigente_hasta), now()))
      into v_desde
    from public.suscripciones_chofer s
    where s.conductor_id = p_conductor and s.estado in ('activa', 'cancelada');
    v_hasta := v_desde + interval '1 month';
  else
    -- Reactivar sin cobro: respeta la fecha que ya tenia. Sin fecha no hay nada
    -- que activar todavia; eso lo hara el cobro.
    select s.vigente_hasta into v_hasta
    from public.suscripciones_chofer s
    where s.referencia_externa = p_referencia;
    if v_hasta is null then
      return null;
    end if;
    -- Si otra fila activa (la cortesia) llegaba mas lejos, esa fecha manda:
    -- cerrarla no puede quitarle dias.
    select greatest(v_hasta, coalesce(max(s.vigente_hasta), v_hasta))
      into v_hasta
    from public.suscripciones_chofer s
    where s.conductor_id = p_conductor and s.estado in ('activa', 'cancelada');
  end if;

  update public.suscripciones_chofer
     set estado = 'vencida', actualizado_en = now()
   where conductor_id = p_conductor
     and estado = 'activa'
     and referencia_externa is distinct from p_referencia;

  insert into public.suscripciones_chofer
    (conductor_id, estado, vigente_hasta, proveedor, referencia_externa,
     monto, moneda, datos, actualizado_en)
  values
    (p_conductor, 'activa', v_hasta, 'paypal', p_referencia,
     coalesce(p_monto, 15), coalesce(p_moneda, 'USD'), p_evento, now())
  on conflict (referencia_externa) do update
    set conductor_id   = excluded.conductor_id,
        estado         = 'activa',
        vigente_hasta  = excluded.vigente_hasta,
        monto          = case when p_sumar_mes then excluded.monto  else public.suscripciones_chofer.monto  end,
        moneda         = case when p_sumar_mes then excluded.moneda else public.suscripciones_chofer.moneda end,
        datos          = excluded.datos,
        actualizado_en = now();

  return v_hasta;
end;
$$;

-- Un cobro devuelto o revertido quita el mes que habia dado. Si con eso ya no
-- le queda tiempo, la cuota pasa a `vencida`.
create or replace function public.revertir_cobro_paypal(p_referencia text, p_evento jsonb)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hasta timestamptz;
begin
  update public.suscripciones_chofer
     set vigente_hasta  = vigente_hasta - interval '1 month',
         estado         = case when vigente_hasta - interval '1 month' <= now()
                               then 'vencida' else estado end,
         datos          = p_evento,
         actualizado_en = now()
   where referencia_externa = p_referencia
     and vigente_hasta is not null
  returning vigente_hasta into v_hasta;

  return v_hasta;
end;
$$;

-- Cancelar no quita el mes que ya se pago. `webhook-paypal` marca `cancelada`
-- al darse de baja (o `SUSPENDED`, si falla la tarjeta) sin tocar
-- `vigente_hasta`, pero esta funcion solo contaba las `activa`: el chofer se
-- quedaba sin viajes en el acto, justo lo contrario de lo que dice el webhook.
create or replace function public.suscripcion_vigente(p_conductor uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.suscripciones_chofer s
    where s.conductor_id = p_conductor
      and s.estado in ('activa', 'cancelada')
      and s.vigente_hasta > now()
  );
$$;
revoke execute on function public.suscripcion_vigente(uuid) from public, anon, authenticated;

revoke execute on function public.aplicar_cobro_paypal(uuid, text, boolean, numeric, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.revertir_cobro_paypal(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.aplicar_cobro_paypal(uuid, text, boolean, numeric, text, jsonb)
  to service_role;
grant execute on function public.revertir_cobro_paypal(text, jsonb) to service_role;
