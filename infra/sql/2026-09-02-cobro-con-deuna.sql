-- Cobrar un viaje con DeUna
-- ------------------------------------------------------------------------
-- Lo que la documentacion de Payvalida deja claro (docs.payvalida.com/api-deuna):
-- el QR se pide con `merchant`, `order`, `timestamp` y un `checksum` SHA-512
-- que incluye un `fixedhash` confidencial. Dice, con esas palabras, que el
-- fixedhash NO debe exponerse en el frontend. Un APK se descompila, asi que la
-- llamada no puede salir del telefono: sale de la Edge Function `cobro-deuna`,
-- que es la unica que ve el secreto.
--
-- De aqui salen tres piezas, y ninguna depende de los datos que faltan:
--
-- 1. `deuna` como metodo de pago, al lado de efectivo y tarjeta.
-- 2. `cobro_deuna` — le da a la Edge Function el numero de orden y el monto.
--    El monto lo pone la base, no el cliente: la regla de siempre.
-- 3. `confirmar_cobro_deuna` — marca el cobro y abona al chofer. Es el reves
--    exacto del efectivo: alli el chofer cobra y queda debiendo la comision;
--    aqui cobra la app y le queda debiendo al chofer su 85 %.
--
-- Lo que NO se hace aqui, porque todavia no se sabe: quien avisa de que el
-- pasajero pago. Ver docs/PAGOS.md, «Lo que falta preguntar».

-- 1. El metodo de pago
-- ------------------------------------------------------------------------
alter table public.metodos_pago drop constraint if exists metodos_pago_tipo_check;
alter table public.metodos_pago add constraint metodos_pago_tipo_check
  check (tipo in ('tarjeta', 'efectivo', 'deuna'));

-- DeUna no deja un token en la app: el pasajero paga escaneando, cada vez. El
-- unico tipo que guarda algo es la tarjeta.
alter table public.metodos_pago drop constraint if exists metodos_pago_token_segun_tipo;
alter table public.metodos_pago add constraint metodos_pago_token_segun_tipo
  check ((tipo = 'tarjeta' and detalle_tokenizado is not null)
      or (tipo in ('efectivo', 'deuna') and detalle_tokenizado is null));

create or replace function public.registrar_metodo_pago(
  p_tipo text, p_token text default null, p_predeterminado boolean default true)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_token text := nullif(trim(coalesce(p_token, '')), '');
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;
  if p_tipo not in ('tarjeta','efectivo','deuna') then
    raise exception 'Tipo de pago no valido' using errcode = 'check_violation';
  end if;

  if p_tipo in ('efectivo','deuna') then
    v_token := null;
  elsif v_token is null then
    raise exception 'La tarjeta necesita el token de la pasarela'
      using errcode = 'check_violation';
  else
    -- Barrera contra guardar un numero de tarjeta por error: 13-19 digitos
    -- seguidos, con o sin separadores, no es un token.
    if regexp_replace(v_token, '[\s-]', '', 'g') ~ '^[0-9]{13,19}$' then
      raise exception 'Eso parece un numero de tarjeta. Guarda solo el token de la pasarela'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into public.pasajeros (id) values (v_uid) on conflict do nothing;

  if p_predeterminado then
    update public.metodos_pago set predeterminado = false
     where pasajero_id = v_uid and predeterminado;
  end if;

  insert into public.metodos_pago (pasajero_id, tipo, detalle_tokenizado, predeterminado)
  values (v_uid, p_tipo, v_token, p_predeterminado)
  returning id into v_id;

  return v_id;
end;
$function$;

-- `finalizar_viaje` no cambia: ya deja el pago en 'pendiente' para todo lo que
-- no sea efectivo, y no abona nada hasta que alguien confirme el cobro.

-- 2. Abrir el cobro
-- ------------------------------------------------------------------------
-- La Edge Function llama a esto con el JWT del pasajero, asi que `auth.uid()`
-- es quien pide pagar. Devuelve la orden y el monto; el telefono no manda
-- ninguno de los dos.
create or replace function public.cobro_deuna(p_viaje_id uuid)
 returns table (orden text, monto numeric, estado text)
 language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_pago public.pagos%rowtype;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  select p.* into v_pago
  from public.pagos p
  join public.viajes v on v.id = p.viaje_id
  where p.viaje_id = p_viaje_id
    and v.pasajero_id = v_uid
    and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_pago.id is null then
    raise exception 'Este viaje todavia no tiene un cobro que pagar'
      using errcode = '42501';
  end if;

  if v_pago.estado <> 'pendiente' then
    -- Ni se pide otro QR ni se toca nada: que la pantalla lo cuente.
    return query select v_pago.referencia_externa, v_pago.monto, v_pago.estado;
    return;
  end if;

  -- La orden se fija una vez y se reutiliza. Pedir dos QR del mismo viaje
  -- tiene que dar la misma orden, o el mismo cobro entraria dos veces.
  if v_pago.proveedor is distinct from 'deuna' or v_pago.referencia_externa is null then
    update public.pagos
    set proveedor = 'deuna',
        referencia_externa = coalesce(referencia_externa,
                                      'ride' || replace(v_pago.id::text, '-', '')),
        actualizado_en = now()
    where id = v_pago.id
    returning * into v_pago;
  end if;

  return query select v_pago.referencia_externa, v_pago.monto, v_pago.estado;
end;
$function$;

-- 3. Confirmar el cobro
-- ------------------------------------------------------------------------
-- Esto es lo que mueve dinero, asi que no lo llama la app: lo llama quien
-- tenga la `service_role` —la Edge Function que reciba el aviso de DeUna— o
-- una persona de administracion conciliando a mano.
--
-- Es idempotente a proposito. Un aviso de pasarela se reintenta, y el dia que
-- llegue dos veces no puede abonar dos veces.
create or replace function public.confirmar_cobro_deuna(
  p_orden text, p_pagado boolean default true, p_datos jsonb default null)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare
  v_rol text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user);
  v_pago public.pagos%rowtype;
  v_conductor uuid;
  v_pct numeric;
  v_abono numeric;
begin
  if v_rol not in ('service_role', 'postgres') and not public.es_administrativo() then
    raise exception 'Solo la pasarela o la administracion confirman un cobro'
      using errcode = '42501';
  end if;

  select * into v_pago from public.pagos
  where proveedor = 'deuna' and referencia_externa = p_orden
  for update;

  if v_pago.id is null then
    raise exception 'No existe un cobro con la orden %', p_orden
      using errcode = 'no_data_found';
  end if;

  -- Ya resuelto: se guarda lo que traiga el aviso y se sale sin tocar el saldo.
  if v_pago.estado <> 'pendiente' then
    if p_datos is not null then
      update public.pagos
      set datos = coalesce(datos, '{}'::jsonb) || p_datos, actualizado_en = now()
      where id = v_pago.id;
    end if;
    return v_pago.id;
  end if;

  update public.pagos
  set estado = case when p_pagado then 'completado' else 'fallido' end,
      datos = coalesce(datos, '{}'::jsonb) || coalesce(p_datos, '{}'::jsonb),
      actualizado_en = now()
  where id = v_pago.id;

  if p_pagado then
    -- El porcentaje de LA TARIFA DEL VIAJE, igual que en el efectivo: lo ya
    -- cobrado no se recalcula si mañana cambia el reparto.
    select v.conductor_id, t.porcentaje_conductor into v_conductor, v_pct
    from public.viajes v
    join public.tarifas t on t.id = v.tarifa_id
    where v.id = v_pago.viaje_id;

    v_abono := round(v_pago.monto * coalesce(v_pct, 0.85), 2);

    if v_conductor is not null and v_abono > 0 then
      insert into public.movimientos_chofer
        (conductor_id, viaje_id, tipo, monto, concepto)
      values (v_conductor, v_pago.viaje_id, 'abono_viaje', v_abono,
              'Viaje cobrado con DeUna')
      on conflict do nothing;
    end if;
  end if;

  return v_pago.id;
end;
$function$;

-- Permisos
-- ------------------------------------------------------------------------
-- `from anon, public`: sin `public` el permiso vuelve por la puerta de atras,
-- porque toda funcion nace con execute para public.
revoke execute on function public.cobro_deuna(uuid) from anon, public;
revoke execute on function public.confirmar_cobro_deuna(text, boolean, jsonb) from anon, public;
grant execute on function public.cobro_deuna(uuid) to authenticated;
-- A `authenticated` tambien, pero la funcion se defiende sola: dentro exige
-- service_role o administracion.
grant execute on function public.confirmar_cobro_deuna(text, boolean, jsonb)
  to authenticated, service_role;


-- Comprobacion
-- ------------------------------------------------------------------------
-- Con un viaje finalizado cuyo pago quedo 'pendiente':
--
--   select * from public.cobro_deuna('<viaje_id>');      -- como el pasajero
--   select public.confirmar_cobro_deuna('<orden>');      -- como service_role
--   select estado, proveedor, referencia_externa from public.pagos
--    where viaje_id = '<viaje_id>';                      -- 'completado'
--   select tipo, monto from public.movimientos_chofer
--    where viaje_id = '<viaje_id>';                      -- abono_viaje, +85 %
--
-- Y la segunda llamada a confirmar no debe crear un segundo abono.
