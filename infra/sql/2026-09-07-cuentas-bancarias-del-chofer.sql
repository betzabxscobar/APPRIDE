-- Pago por transferencia: las cuentas bancarias del chofer
-- ---------------------------------------------------------------------------
-- El pasajero copia el número de cuenta del chofer y hace la transferencia
-- desde el banco que use. La app no mueve dinero ni se conecta a ningún banco:
-- solo enseña el dato para copiarlo. Eso es a propósito —conectarse a un banco
-- exige un convenio y una pasarela— y hay que decirlo claro en la pantalla,
-- porque cambia quién responde si el dinero no llega.
--
-- Un número de cuenta es dato sensible. Por eso NO se leen por RLS abierta:
-- salen por `cuentas_del_chofer(viaje)`, que comprueba que quien pregunta sea
-- el pasajero de ese viaje. Sin viaje de por medio, nadie ve la cuenta de
-- nadie.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. Catálogo de bancos
-- ---------------------------------------------------------------------------
-- Va en tabla y no en un `check` para que mañana se añada un banco sin migrar
-- nada. `logo` es la clave del asset que la app trae empaquetado; si está en
-- null —o el archivo no existe— la app dibuja las iniciales y no se rompe.
-- Los colores salen del propio logo, no de una estimación.
create table if not exists public.bancos (
  id text primary key,
  nombre text not null,
  logo text,
  color text,
  orden smallint not null default 0,
  activo boolean not null default true
);

insert into public.bancos (id, nombre, logo, color, orden) values
  ('pichincha',     'Banco Pichincha',     'banco_pichincha',     '#FFDD00', 1),
  ('guayaquil',     'Banco Guayaquil',     'banco_guayaquil',     '#D2006E', 2),
  ('internacional', 'Banco Internacional', 'banco_internacional', '#F5821F', 3),
  ('produbanco',    'Produbanco',          'produbanco',          '#00713C', 4)
on conflict (id) do update
  set nombre = excluded.nombre,
      logo   = excluded.logo,
      color  = excluded.color,
      orden  = excluded.orden;

alter table public.bancos enable row level security;

drop policy if exists bancos_lectura on public.bancos;
create policy bancos_lectura on public.bancos
  for select to authenticated using (activo);


-- 2. Las cuentas del chofer
-- ---------------------------------------------------------------------------
create table if not exists public.cuentas_bancarias_chofer (
  id uuid primary key default gen_random_uuid(),
  conductor_id uuid not null references public.conductores(id) on delete cascade,
  banco text not null references public.bancos(id),
  tipo text not null check (tipo in ('ahorros','corriente')),
  numero text not null check (numero ~ '^[0-9]{6,20}$'),
  titular text not null check (length(trim(titular)) >= 3),
  cedula_titular text,
  predeterminada boolean not null default false,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  -- La misma cuenta, en el mismo banco, no se registra dos veces.
  unique (conductor_id, banco, numero)
);

create index if not exists cuentas_bancarias_chofer_conductor_idx
  on public.cuentas_bancarias_chofer (conductor_id) where activa;

alter table public.cuentas_bancarias_chofer enable row level security;

-- El chofer manda sobre sus cuentas. El pasajero NO entra por aqui: para el
-- estan la funcion `cuentas_del_chofer`, que exige un viaje en comun.
drop policy if exists cuentas_chofer_propias on public.cuentas_bancarias_chofer;
create policy cuentas_chofer_propias on public.cuentas_bancarias_chofer
  for all to authenticated
  using (conductor_id = (select auth.uid()) or public.es_administrativo())
  with check (conductor_id = (select auth.uid()));


-- 3. Registrar o editar una cuenta
-- ---------------------------------------------------------------------------
create or replace function public.registrar_cuenta_bancaria(
  p_banco text,
  p_tipo text,
  p_numero text,
  p_titular text,
  p_cedula_titular text default null,
  p_predeterminada boolean default true,
  p_cuenta_id uuid default null
)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_numero text;
  v_cedula text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  if not exists (select 1 from public.conductores where id = v_uid) then
    raise exception 'Solo un chofer registra cuentas para cobrar'
      using errcode = '42501';
  end if;

  if not exists (select 1 from public.bancos where id = p_banco and activo) then
    raise exception 'Ese banco no esta disponible' using errcode = 'check_violation';
  end if;

  -- Se quitan espacios y guiones, que es como se copia el numero del banco,
  -- pero NADA mas. Borrar en silencio una letra mal tecleada dejaria un numero
  -- mas corto, igual de valido y de otra persona: el dinero se iria a una
  -- cuenta ajena sin que nadie lo notara.
  v_numero := regexp_replace(coalesce(p_numero, ''), '[\s-]', '', 'g');
  if v_numero !~ '^[0-9]{6,20}$' then
    raise exception 'El numero de cuenta son solo digitos, entre 6 y 20'
      using errcode = 'check_violation';
  end if;

  -- La cedula del titular es opcional, pero si viene tiene que ser real: es lo
  -- que el pasajero coteja al transferir. Misma regla con las letras.
  v_cedula := nullif(regexp_replace(coalesce(p_cedula_titular, ''), '[\s-]', '', 'g'), '');
  if v_cedula is not null and v_cedula !~ '^[0-9]{10}$' then
    raise exception 'La cedula del titular son diez digitos'
      using errcode = 'check_violation';
  end if;
  if v_cedula is not null and not public.cedula_ecuatoriana_valida(v_cedula) then
    raise exception 'La cedula del titular no es valida'
      using errcode = 'check_violation';
  end if;

  if p_predeterminada then
    update public.cuentas_bancarias_chofer
    set predeterminada = false
    where conductor_id = v_uid and predeterminada;
  end if;

  if p_cuenta_id is null then
    insert into public.cuentas_bancarias_chofer
      (conductor_id, banco, tipo, numero, titular, cedula_titular, predeterminada)
    values (v_uid, p_banco, p_tipo, v_numero, trim(p_titular), v_cedula, p_predeterminada)
    returning id into v_id;
  else
    update public.cuentas_bancarias_chofer
    set banco = p_banco,
        tipo = p_tipo,
        numero = v_numero,
        titular = trim(p_titular),
        cedula_titular = v_cedula,
        predeterminada = p_predeterminada,
        activa = true
    where id = p_cuenta_id and conductor_id = v_uid
    returning id into v_id;

    if v_id is null then
      raise exception 'Esa cuenta no es tuya' using errcode = '42501';
    end if;
  end if;

  return v_id;
end;
$function$;


-- 4. Borrar una cuenta
-- ---------------------------------------------------------------------------
create or replace function public.eliminar_cuenta_bancaria(p_cuenta_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_borradas int;
begin
  delete from public.cuentas_bancarias_chofer
  where id = p_cuenta_id and conductor_id = v_uid;

  get diagnostics v_borradas = row_count;
  if v_borradas = 0 then
    raise exception 'Esa cuenta no es tuya' using errcode = '42501';
  end if;
end;
$function$;


-- 5. Las cuentas que ve el pasajero
-- ---------------------------------------------------------------------------
-- La unica puerta por la que un pasajero llega a la cuenta de un chofer, y
-- solo con un viaje suyo de por medio. Es `definer` justo para eso: la RLS de
-- la tabla no le deja pasar, y aqui se comprueba a mano lo que si vale.
create or replace function public.cuentas_del_chofer(p_viaje_id uuid)
 returns table (
   id uuid,
   banco text,
   banco_nombre text,
   banco_logo text,
   banco_color text,
   tipo text,
   numero text,
   titular text,
   cedula_titular text,
   predeterminada boolean
 )
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_conductor uuid;
begin
  select v.conductor_id into v_conductor
  from public.viajes v
  where v.id = p_viaje_id
    and (v_uid in (v.pasajero_id, v.conductor_id) or public.es_administrativo());

  if v_conductor is null then
    raise exception 'Ese viaje no es tuyo, o todavia no tiene chofer'
      using errcode = '42501';
  end if;

  return query
  select c.id, c.banco, b.nombre, b.logo, b.color,
         c.tipo, c.numero, c.titular, c.cedula_titular, c.predeterminada
  from public.cuentas_bancarias_chofer c
  join public.bancos b on b.id = c.banco
  where c.conductor_id = v_conductor and c.activa and b.activo
  order by c.predeterminada desc, b.orden;
end;
$function$;


-- 6. `transferencia` como método de pago
-- ---------------------------------------------------------------------------
create or replace function public.registrar_metodo_pago(
  p_tipo text,
  p_token text default null,
  p_predeterminado boolean default true
)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_token text := nullif(trim(coalesce(p_token, '')), '');
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;
  if p_tipo not in ('tarjeta','efectivo','deuna','transferencia') then
    raise exception 'Tipo de pago no valido' using errcode = 'check_violation';
  end if;

  -- La transferencia no guarda nada del pasajero: el dato que importa es la
  -- cuenta del chofer, y esa vive en su ficha, no aqui.
  if p_tipo in ('efectivo','deuna','transferencia') then
    v_token := null;
  elsif v_token is null then
    raise exception 'La tarjeta necesita el token de la pasarela'
      using errcode = 'check_violation';
  else
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


-- 7. El chofer confirma que le llegó el dinero
-- ---------------------------------------------------------------------------
-- La transferencia tiene el mismo problema que el efectivo: la app no se entera
-- sola. El unico que sabe si entro es el chofer, mirando su banco.
--
-- `confirmar_pago_efectivo` se queda como estaba de puertas afuera —la app la
-- sigue llamando— pero por dentro delega aqui.
create or replace function public.confirmar_pago_recibido(p_viaje_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    and v.estado = 'FINALIZADO'
    and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_pago_id is null then
    raise exception 'Ese viaje no es tuyo o todavia no tiene cobro'
      using errcode = '42501';
  end if;

  -- DeUna la confirma la pasarela, no el chofer a mano: si no, cualquiera
  -- podria dar por cobrado un QR que nadie pago.
  if v_tipo not in ('efectivo','transferencia') then
    raise exception 'Ese cobro lo confirma la pasarela, no el chofer'
      using errcode = 'check_violation';
  end if;

  if v_estado = 'completado' then
    return;
  end if;

  update public.pagos
  set estado = 'completado', actualizado_en = now()
  where id = v_pago_id;

  -- El dinero ya lo tiene el chofer —en la mano o en su cuenta—, asi que la
  -- comision pasa a ser deuda suya. Con el porcentaje de LA TARIFA DEL VIAJE.
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
$function$;

create or replace function public.confirmar_pago_efectivo(p_viaje_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform public.confirmar_pago_recibido(p_viaje_id);
end;
$function$;


-- 8. Permisos
-- ---------------------------------------------------------------------------
revoke execute on function public.registrar_cuenta_bancaria(text, text, text, text, text, boolean, uuid) from public, anon;
revoke execute on function public.eliminar_cuenta_bancaria(uuid) from public, anon;
revoke execute on function public.cuentas_del_chofer(uuid) from public, anon;
revoke execute on function public.confirmar_pago_recibido(uuid) from public, anon;

grant execute on function public.registrar_cuenta_bancaria(text, text, text, text, text, boolean, uuid) to authenticated;
grant execute on function public.eliminar_cuenta_bancaria(uuid) to authenticated;
grant execute on function public.cuentas_del_chofer(uuid) to authenticated;
grant execute on function public.confirmar_pago_recibido(uuid) to authenticated;

grant select on public.bancos to authenticated;
grant select, insert, update, delete on public.cuentas_bancarias_chofer to authenticated;
