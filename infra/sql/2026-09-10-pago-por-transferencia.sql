-- El pasajero paga por transferencia, y alguien lo comprueba
-- ---------------------------------------------------------------------------
-- Se retira DeUna. En su lugar el pasajero transfiere a la cuenta del chofer
-- desde la app de su propio banco: Ride no toca ese dinero, solo enseña el
-- numero de cuenta.
--
-- Eso deja una pregunta que el efectivo no tenia: ¿como se sabe que pago? Con
-- efectivo el chofer lo tiene en la mano. Con una transferencia hay que
-- esperar a que aparezca en el banco, y el unico que puede verlo es el chofer.
-- Asi que la comprobacion son dos pasos y dos personas:
--
--   1. El pasajero transfiere, sube la foto del comprobante y avisa.
--      -> `reportar_transferencia()`
--   2. El chofer mira su banco, contrasta con el comprobante y confirma.
--      -> `confirmar_pago_recibido()`, que ya existia para el efectivo
--
-- Y el viaje NO se cierra hasta el paso 2. Eso obliga a mover el cobro: hasta
-- ahora nacia dentro de `finalizar_viaje`, o sea que no existia hasta el final.
-- Si el cierre depende del cobro y el cobro del cierre, no arranca ninguno de
-- los dos. Ahora, cuando el metodo es transferencia, el cobro nace al empezar
-- el viaje: asi el pasajero puede ir pagando por el camino y al llegar solo
-- queda confirmar.
--
-- Se aplica con:
--   supabase db push
-- o pegandolo entero en el editor SQL del proyecto.

-- ---------------------------------------------------------------------------
-- 1. `transferencia` sustituye a `deuna`
-- ---------------------------------------------------------------------------
-- `confirmar_pago_recibido()` ya nombraba 'transferencia', pero la tabla no lo
-- admitia: esa rama del codigo no se habia podido ejecutar nunca.

-- Primero se sueltan, luego se migra y al final se vuelven a poner: el `update`
-- cambia las filas a un valor que la restriccion vieja todavia no admite, y si
-- se hace al reves rebota.
alter table public.metodos_pago drop constraint if exists metodos_pago_tipo_check;
alter table public.metodos_pago drop constraint if exists metodos_pago_token_segun_tipo;

update public.metodos_pago set tipo = 'transferencia' where tipo = 'deuna';

alter table public.metodos_pago add constraint metodos_pago_tipo_check
  check (tipo in ('tarjeta', 'efectivo', 'transferencia'));

alter table public.metodos_pago add constraint metodos_pago_token_segun_tipo
  check (
    (tipo = 'tarjeta' and detalle_tokenizado is not null)
    or (tipo in ('efectivo', 'transferencia') and detalle_tokenizado is null)
  );

-- ---------------------------------------------------------------------------
-- 2. Donde vive el comprobante
-- ---------------------------------------------------------------------------

alter table public.pagos
  add column if not exists comprobante_url text,
  add column if not exists reportado_en timestamptz;

comment on column public.pagos.comprobante_url is
  'Foto del comprobante que subio el pasajero. Es la prueba que queda si mas '
  'tarde se discute si el dinero se envio o no.';
comment on column public.pagos.reportado_en is
  'Cuando el pasajero dijo que ya transfirio. No es que haya llegado: eso lo '
  'confirma el chofer mirando su banco.';

-- El deposito de los comprobantes. Privado: un comprobante lleva numero de
-- cuenta, nombre y monto, y no tiene por que ser publico.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprobantes', 'comprobantes', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- El pasajero sube el suyo, en una carpeta con su uuid.
drop policy if exists comprobantes_sube_el_pasajero on storage.objects;
create policy comprobantes_sube_el_pasajero
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'comprobantes'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Lo ven los dos del viaje: el que lo subio y el chofer que tiene que
-- contrastarlo. Y la administracion, para resolver reclamos.
drop policy if exists comprobantes_lo_ven_los_del_viaje on storage.objects;
create policy comprobantes_lo_ven_los_del_viaje
  on storage.objects for select to authenticated
  using (
    bucket_id = 'comprobantes'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.es_superadmin()
      or exists (
        select 1
        from public.pagos p
        join public.viajes v on v.id = p.viaje_id
        where p.comprobante_url = storage.objects.name
          and v.conductor_id = (select auth.uid())
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 3. El pasajero avisa de que transfirio
-- ---------------------------------------------------------------------------

create or replace function public.reportar_transferencia(
  p_viaje_id uuid,
  p_comprobante text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pago uuid;
  v_estado text;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  select p.id, p.estado into v_pago, v_estado
  from public.pagos p
  join public.viajes v on v.id = p.viaje_id
  where p.viaje_id = p_viaje_id
    and v.pasajero_id = v_uid
    and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_pago is null then
    raise exception 'Ese viaje no es tuyo o todavia no tiene cobro'
      using errcode = '42501';
  end if;

  -- Ya cobrado: avisar otra vez no cambia nada, pero tampoco es un error del
  -- que haya que quejarse. Se sale sin tocar nada.
  if v_estado = 'completado' then
    return;
  end if;

  update public.pagos
  set reportado_en = now(),
      comprobante_url = coalesce(p_comprobante, comprobante_url),
      actualizado_en = now()
  where id = v_pago;

  -- Que al chofer le salte, que es quien tiene que ir a mirar su banco.
  insert into public.notificaciones (usuario_id, titulo, mensaje)
  select v.conductor_id,
         'El pasajero dice que ya transfirio',
         'Revisa tu banco y confirma el cobro para poder cerrar el viaje.'
  from public.viajes v
  where v.id = p_viaje_id and v.conductor_id is not null;
end;
$$;

comment on function public.reportar_transferencia(uuid, text) is
  'El pasajero avisa de que transfirio y adjunta el comprobante. NO da el pago '
  'por cobrado: eso lo hace el chofer con confirmar_pago_recibido().';

revoke execute on function public.reportar_transferencia(uuid, text) from public, anon;
grant execute on function public.reportar_transferencia(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El cobro por transferencia nace al empezar el viaje
-- ---------------------------------------------------------------------------
-- Con efectivo o tarjeta sigue naciendo al final, como siempre. Solo la
-- transferencia se adelanta, porque es la unica cuyo cierre depende de que ya
-- este cobrada.

create or replace function public.abrir_cobro_si_es_transferencia(p_viaje_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_metodo uuid;
  v_tipo text;
  v_monto numeric;
  v_pasajero uuid;
begin
  select v.tarifa_estimada, v.pasajero_id into v_monto, v_pasajero
  from public.viajes v where v.id = p_viaje_id;

  select m.id, m.tipo into v_metodo, v_tipo
  from public.metodos_pago m
  where m.pasajero_id = v_pasajero and m.predeterminado
  limit 1;

  if coalesce(v_tipo, 'efectivo') <> 'transferencia' then
    return;
  end if;

  if exists (
    select 1 from public.pagos
    where viaje_id = p_viaje_id and tipo = 'pago'
  ) then
    return;
  end if;

  insert into public.pagos (viaje_id, metodo_pago_id, monto, tipo, estado, proveedor)
  values (p_viaje_id, v_metodo, v_monto, 'pago', 'pendiente', 'transferencia');
end;
$$;

revoke execute on function public.abrir_cobro_si_es_transferencia(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. El chofer confirma; se admite hacerlo antes de cerrar
-- ---------------------------------------------------------------------------
-- Antes exigia que el viaje ya estuviera FINALIZADO. Con transferencia eso es
-- imposible: el cierre espera al cobro. Ahora vale tambien EN_CURSO.

create or replace function public.confirmar_pago_recibido(p_viaje_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pago_id uuid;
  v_monto numeric;
  v_estado text;
  v_tipo text;
  v_pct numeric;
  v_comision numeric;
begin
  select p.id, p.monto, p.estado, coalesce(m.tipo, 'efectivo'), t.porcentaje_conductor
    into v_pago_id, v_monto, v_estado, v_tipo, v_pct
  from public.pagos p
  join public.viajes v on v.id = p.viaje_id
  join public.tarifas t on t.id = v.tarifa_id
  left join public.metodos_pago m on m.id = p.metodo_pago_id
  where p.viaje_id = p_viaje_id
    and v.conductor_id = v_uid
    and v.estado in ('FINALIZADO', 'EN_CURSO')
    and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_pago_id is null then
    raise exception 'Ese viaje no es tuyo o todavia no tiene cobro'
      using errcode = '42501';
  end if;

  if v_tipo not in ('efectivo', 'transferencia') then
    raise exception 'Ese cobro lo confirma la pasarela, no el chofer'
      using errcode = 'check_violation';
  end if;

  if v_estado = 'completado' then
    return;
  end if;

  update public.pagos
  set estado = 'completado', actualizado_en = now()
  where id = v_pago_id;

  v_comision := v_monto - round(v_monto * coalesce(v_pct, 0.85), 2);

  if v_comision > 0 then
    insert into public.movimientos_chofer
      (conductor_id, viaje_id, tipo, monto, concepto)
    values (v_uid, p_viaje_id, 'comision', -v_comision,
            case when v_tipo = 'transferencia'
                 then 'Comision del viaje cobrado por transferencia'
                 else 'Comision del viaje cobrado en efectivo' end)
    on conflict do nothing;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Ya no hay pasarela DeUna
-- ---------------------------------------------------------------------------

drop function if exists public.cobro_deuna(uuid);
drop function if exists public.confirmar_cobro_deuna(text, boolean, jsonb);

-- ---------------------------------------------------------------------------
-- 7. Enganchar el cobro al arranque del viaje
-- ---------------------------------------------------------------------------
-- Se repite el cuerpo entero porque `create or replace function` no admite
-- parches. Lo unico que cambia respecto a la version anterior va marcado.

create or replace function public.avanzar_viaje(p_viaje_id uuid, p_codigo text default null)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_estado text;
  v_siguiente text;
  v_codigo text;
  v_intentos smallint;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  select v.estado::text into v_estado
  from public.viajes v
  where v.id = p_viaje_id and v.conductor_id = v_uid;

  if v_estado is null then
    raise exception 'Ese viaje no es tuyo' using errcode = '42501';
  end if;

  v_siguiente := case v_estado
    when 'ACEPTADO' then 'CONDUCTOR_EN_CAMINO'
    when 'CONDUCTOR_EN_CAMINO' then 'CONDUCTOR_EN_ORIGEN'
    when 'CONDUCTOR_EN_ORIGEN' then 'EN_CURSO'
    else null
  end;

  if v_siguiente is null then
    raise exception 'Este viaje ya no puede avanzar mas'
      using errcode = 'check_violation';
  end if;

  -- El salto que arranca el viaje exige el codigo del pasajero.
  if v_siguiente = 'EN_CURSO' then
    select c.codigo, c.intentos into v_codigo, v_intentos
    from public.codigos_viaje c where c.viaje_id = p_viaje_id;

    if v_codigo is null then
      raise exception 'Este viaje no tiene codigo de inicio'
        using errcode = 'check_violation';
    end if;

    if v_intentos >= 5 then
      raise exception 'Demasiados intentos. Pidele al pasajero que cancele y vuelva a pedir el viaje'
        using errcode = 'check_violation';
    end if;

    if coalesce(trim(p_codigo), '') <> v_codigo then
      update public.codigos_viaje
      set intentos = intentos + 1
      where viaje_id = p_viaje_id;

      raise exception 'El codigo no coincide' using errcode = 'check_violation';
    end if;

    update public.codigos_viaje
    set usado_en = now()
    where viaje_id = p_viaje_id;
  end if;

  update public.viajes
  set estado = v_siguiente::public.enum_estado_viaje,
      fecha_inicio = case when v_siguiente = 'EN_CURSO'
                          then now() else fecha_inicio end
  where id = p_viaje_id;

  -- NUEVO: si paga por transferencia, el cobro se abre ya, para que el
  -- pasajero pueda ir transfiriendo por el camino en vez de tener a todo el
  -- mundo esperando al llegar.
  if v_siguiente = 'EN_CURSO' then
    perform public.abrir_cobro_si_es_transferencia(p_viaje_id);
  end if;

  return v_siguiente;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Sin cobro confirmado, la transferencia no deja cerrar el viaje
-- ---------------------------------------------------------------------------

create or replace function public.finalizar_viaje(p_viaje_id uuid)
returns numeric
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_estimada numeric;
  v_metodo uuid;
  v_pasajero uuid;
  v_tarifa uuid;
  v_inicio timestamptz;
  v_dest_lat double precision;
  v_dest_lng double precision;
  v_org_lat double precision;
  v_org_lng double precision;
  v_lat double precision;
  v_lng double precision;
  v_al_destino numeric;
  v_recorrido numeric;
  v_recta numeric;
  v_verificada boolean;
  v_desvio boolean := false;
  v_tipo text;
  v_estado_pago text;
begin
  select tarifa_estimada, pasajero_id, tarifa_id, fecha_inicio
    into v_estimada, v_pasajero, v_tarifa, v_inicio
  from public.viajes
  where id = p_viaje_id and conductor_id = v_uid and estado = 'EN_CURSO';

  if v_estimada is null then
    raise exception 'Solo el conductor puede cerrar un viaje en curso'
      using errcode = '42501';
  end if;

  if v_inicio is not null
     and now() - v_inicio < make_interval(secs => public.duracion_minima_viaje_seg()) then
    raise exception 'El viaje acaba de empezar. Espera a llegar al destino.'
      using errcode = 'check_violation';
  end if;

  -- NUEVO: con transferencia, el viaje no se cierra hasta que el chofer haya
  -- visto el dinero en su banco. Es la unica forma de cobro donde el chofer no
  -- tiene el dinero delante al terminar: si se dejara cerrar antes, el pasajero
  -- se baja y el cobro se queda colgado sin nadie a quien reclamar.
  select coalesce(m.tipo, 'efectivo'), p.estado into v_tipo, v_estado_pago
  from public.pagos p
  left join public.metodos_pago m on m.id = p.metodo_pago_id
  where p.viaje_id = p_viaje_id and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_tipo = 'transferencia' and coalesce(v_estado_pago, 'pendiente') <> 'completado' then
    raise exception 'Confirma que te llego la transferencia para poder cerrar el viaje'
      using errcode = 'check_violation';
  end if;

  select latitud, longitud into v_dest_lat, v_dest_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'destino' limit 1;

  select latitud, longitud into v_org_lat, v_org_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'origen' limit 1;

  select latitud, longitud into v_lat, v_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'posicion_actual'
  order by registrado_en desc limit 1;

  if v_lat is null or v_dest_lat is null then
    -- Sin rastro no hay con que comprobar. Se deja cerrar —el pasajero esta
    -- ahi esperando y no puede quedarse atrapado en un viaje abierto—, pero
    -- queda marcado para que administracion lo revise.
    v_verificada := null;
  else
    v_al_destino := public.distancia_km(v_lat, v_lng, v_dest_lat, v_dest_lng)::numeric;

    if v_al_destino > public.radio_llegada_km() then
      raise exception
        'Todavia no estas en el destino: faltan % km. El viaje se cierra al llegar.',
        round(v_al_destino, 2)
        using errcode = 'check_violation';
    end if;

    v_verificada := true;
  end if;

  v_recorrido := public.recorrido_km(p_viaje_id);

  if v_org_lat is not null and v_dest_lat is not null then
    v_recta := public.distancia_km(v_org_lat, v_org_lng, v_dest_lat, v_dest_lng)::numeric;
    v_desvio := v_recta > 0
            and v_recorrido > v_recta * public.desvio_maximo_factor();
  end if;

  update public.viajes
  set estado = 'FINALIZADO',
      fecha_fin = now(),
      tarifa_final = v_estimada,
      distancia_recorrida_km = v_recorrido,
      llegada_verificada = v_verificada,
      desvio_detectado = v_desvio
  where id = p_viaje_id;

  select id into v_metodo
  from public.metodos_pago
  where pasajero_id = v_pasajero and predeterminado
  limit 1;

  -- Todo cobro nace pendiente, el efectivo tambien. Antes el efectivo entraba
  -- como 'completado' sin que nadie lo hubiera visto: eso no era saber que el
  -- pasajero pago, era suponerlo. Lo confirma el chofer con
  -- `confirmar_pago_recibido`, y con el pasa la comision a su cuenta.
  --
  -- NUEVO: si ya existe —la transferencia lo abre al empezar el viaje— no se
  -- crea un segundo.
  if not exists (
    select 1 from public.pagos where viaje_id = p_viaje_id and tipo = 'pago'
  ) then
    insert into public.pagos (viaje_id, metodo_pago_id, monto, tipo, estado)
    values (p_viaje_id, v_metodo, v_estimada, 'pago', 'pendiente');
  end if;

  return v_estimada;
end;
$$;
