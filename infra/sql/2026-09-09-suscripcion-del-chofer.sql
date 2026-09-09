-- La cuota mensual que paga el chofer para recibir viajes
-- ---------------------------------------------------------------------------
-- Son 15 USD al mes. Sin ellos el chofer entra a la app, ve su perfil y su
-- historial, pero no se puede poner en linea ni aceptar nada.
--
-- El corte NO puede vivir solo en la app. Un APK se descompila y el telefono
-- llama a PostgREST directamente, asi que el que manda es el servidor: aqui
-- estan las tres puertas por las que se pasa para trabajar, y las tres
-- preguntan por la suscripcion.
--
--   1. ponerse `disponible`      -> trigger `conductor_disponible_con_cuota`
--   2. ver solicitudes abiertas  -> `solicitudes_abiertas()`
--   3. aceptar un viaje          -> `aceptar_viaje()`
--
-- La 3 es la que de verdad protege el dinero. Las otras dos son para que el
-- chofer se entere antes y no despues de haber intentado tomar un viaje.
--
-- Quien cobra es PayPal. Esta tabla no la escribe nunca el telefono: la unica
-- que la toca es la Edge Function `webhook-paypal` con la service_role, porque
-- si el cliente pudiera marcar su propia suscripcion como activa el cobro no
-- serviria de nada. Ver infra/edge/webhook-paypal/index.ts y docs/PAGOS.md.
--
-- Se aplica con:
--   supabase db push
-- o pegandolo entero en el editor SQL del proyecto.

-- ---------------------------------------------------------------------------
-- 1. La tabla
-- ---------------------------------------------------------------------------

create table if not exists public.suscripciones_chofer (
  id uuid primary key default gen_random_uuid(),
  conductor_id uuid not null
    references public.conductores(id) on delete cascade,

  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'activa', 'vencida', 'cancelada')),

  -- Hasta cuando puede trabajar. Es la fecha la que manda, no el estado: el
  -- estado se queda viejo en cuanto pasa el tiempo y nadie lo actualiza, la
  -- fecha no. Por eso `suscripcion_vigente()` mira las dos cosas.
  vigente_hasta timestamptz,

  proveedor text not null default 'paypal',

  -- El id de la suscripcion en PayPal (`I-XXXXXXXX`). Unico a proposito: el
  -- webhook de PayPal reintenta el mismo evento si algo falla, y sin esto un
  -- reintento crearia una segunda suscripcion para el mismo chofer.
  referencia_externa text unique,

  monto numeric not null default 15 check (monto >= 0),
  moneda text not null default 'USD',

  -- El evento de PayPal tal cual llego, para poder reconstruir un cobro que se
  -- discuta meses despues.
  datos jsonb,

  created_at timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  -- Una suscripcion activa sin fecha de fin dejaria trabajar para siempre.
  constraint suscripcion_activa_con_fecha
    check (estado <> 'activa' or vigente_hasta is not null)
);

comment on table public.suscripciones_chofer is
  'Cuota mensual del chofer para recibir viajes. La escribe solo la Edge '
  'Function webhook-paypal con la service_role; el telefono nunca.';

-- Un chofer no puede tener dos suscripciones activas a la vez.
create unique index if not exists suscripciones_chofer_una_activa
  on public.suscripciones_chofer (conductor_id)
  where estado = 'activa';

create index if not exists suscripciones_chofer_vigencia
  on public.suscripciones_chofer (conductor_id, vigente_hasta desc);

-- ---------------------------------------------------------------------------
-- 2. La pregunta: ¿este chofer puede trabajar hoy?
-- ---------------------------------------------------------------------------
-- `security definer` porque la usan las politicas y los triggers, y tiene que
-- poder mirar la tabla aunque el RLS del que pregunta no le deje.

create or replace function public.suscripcion_vigente(p_conductor uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.suscripciones_chofer s
    where s.conductor_id = p_conductor
      and s.estado = 'activa'
      and s.vigente_hasta > now()
  );
$$;

comment on function public.suscripcion_vigente(uuid) is
  'True si el chofer tiene la cuota mensual al dia. Mira la fecha, no solo el '
  'estado: una suscripcion activa cuya fecha ya paso no vale.';

-- Lo que la app necesita pintar en el panel. Devuelve una fila siempre, aunque
-- el chofer no haya pagado nunca: asi la pantalla no tiene que distinguir
-- entre "no hay datos" y "error de red".
--
-- La fila que devuelve es la que MANDA, o sea la que le deja trabajar, no la
-- ultima que se creo. Cogiendo la ultima se mezclaban dos: un chofer con el
-- mes de cortesia que abria una suscripcion en PayPal y no la pagaba veia
-- "Al dia" con los datos de la de PayPal delante, como si hubiera pagado. Se
-- vio en el telefono, no en las pruebas.
--
-- `pago_sin_terminar` es esa suscripcion abierta y sin aprobar. No sirve para
-- trabajar, pero se devuelve para poder avisarla: si no, el chofer se queda
-- creyendo que pago.
create or replace function public.mi_suscripcion()
returns table (
  estado text,
  vigente_hasta timestamptz,
  dias_restantes integer,
  vigente boolean,
  monto numeric,
  moneda text,
  proveedor text,
  referencia_externa text,
  pago_sin_terminar text
)
language sql
stable
security definer
set search_path to ''
as $$
  with yo as (select auth.uid() as uid),
  manda as (
    select s.*
    from public.suscripciones_chofer s, yo
    where s.conductor_id = yo.uid
    order by
      (s.estado = 'activa' and s.vigente_hasta > now()) desc,
      s.vigente_hasta desc nulls last,
      s.created_at desc
    limit 1
  ),
  sin_terminar as (
    select s.referencia_externa
    from public.suscripciones_chofer s, yo
    where s.conductor_id = yo.uid
      and s.estado = 'pendiente'
      and s.referencia_externa is not null
    order by s.created_at desc
    limit 1
  )
  select
    coalesce(m.estado, 'pendiente'),
    m.vigente_hasta,
    case
      when m.vigente_hasta is null then null
      -- Hacia arriba: a quien le quedan 3 horas le quedan "1 dia", no "0".
      else greatest(0, ceil(extract(epoch from (m.vigente_hasta - now())) / 86400))::integer
    end,
    public.suscripcion_vigente((select uid from yo)),
    coalesce(m.monto, 15),
    coalesce(m.moneda, 'USD'),
    coalesce(m.proveedor, 'paypal'),
    m.referencia_externa,
    (select referencia_externa from sin_terminar)
  from (select 1) _
  left join manda m on true;
$$;

-- ---------------------------------------------------------------------------
-- 3. Puerta 1: ponerse en linea
-- ---------------------------------------------------------------------------
-- No se puede hacer con un CHECK como `conductores_disponible_requiere_aprobacion`:
-- un CHECK no puede consultar otra tabla ni usar now(). Tiene que ser trigger.

create or replace function public.conductor_disponible_con_cuota()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.disponible
     and not public.suscripcion_vigente(new.id)
     and not public.es_superadmin() then

    if new.disponible is distinct from coalesce(old.disponible, false) then
      -- Esta intentando encenderse ahora mismo: se le dice por que no puede.
      raise exception 'conductor_sin_suscripcion'
        using errcode = 'check_violation',
              hint = 'Paga la cuota mensual para poder recibir viajes';
    else
      -- Ya venia en linea y se le vencio la cuota mientras tanto. Aqui NO se
      -- lanza excepcion: el unico update que llega en ese caso es el reporte
      -- de posicion, que corre cada 30 segundos, y reventarlo dejaria al
      -- chofer sin poder ni actualizarse. Se le baja el interruptor y deja de
      -- recibir viajes.
      --
      -- Mirar solo la transicion apagado->encendido no bastaba: el que ya
      -- estaba en linea cuando le vencio se quedaba trabajando para siempre.
      -- Salio probando con un rol `authenticated` de verdad.
      new.disponible := false;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists conductor_disponible_con_cuota on public.conductores;
create trigger conductor_disponible_con_cuota
  before update on public.conductores
  for each row
  execute function public.conductor_disponible_con_cuota();

-- ---------------------------------------------------------------------------
-- 4. Puerta 2: la lista de oportunidades
-- ---------------------------------------------------------------------------
-- Se reescribe entera porque `create or replace function` no admite parches:
-- hay que repetir el cuerpo. Lo unico que cambia respecto a
-- 2026-09-07-solicitudes-abiertas-para-el-chofer.sql es el filtro de la cuota,
-- marcado abajo. Si se toca aquella, hay que traer el cambio aqui.

create or replace function public.solicitudes_abiertas()
returns table (
  id uuid,
  estado text,
  pasajero_id uuid,
  tarifa_estimada numeric,
  tarifa_nombre text,
  fecha_solicitud timestamptz,
  origen_lat double precision,
  origen_lng double precision,
  origen_texto text,
  origen_referencia text,
  destino_lat double precision,
  destino_lng double precision,
  destino_texto text,
  destino_referencia text,
  categoria text,
  categoria_nombre text,
  categoria_icono text,
  gana_conductor numeric,
  distancia_km numeric,
  minutos_estimados integer,
  zona_origen text
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    v.id,
    v.estado::text,
    v.pasajero_id,
    v.tarifa_estimada,
    t.nombre,
    v.fecha_solicitud,
    o.latitud, o.longitud, o.direccion_texto, o.referencia,
    d.latitud, d.longitud, d.direccion_texto, d.referencia,
    v.categoria, cat.nombre, cat.icono,
    round(v.tarifa_estimada * t.porcentaje_conductor, 2),
    round(public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)::numeric, 1),
    greatest(1, round(
      public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)
      / public.velocidad_media_kmh() * 60)::integer),
    public.zona_de(o.latitud, o.longitud)
  from public.viajes v
  join public.tarifas t on t.id = v.tarifa_id
  left join public.categorias_vehiculo cat on cat.id = v.categoria
  left join public.ubicaciones o on o.viaje_id = v.id and o.tipo = 'origen'
  left join public.ubicaciones d on d.viaje_id = v.id and d.tipo = 'destino'
  where v.estado = 'BUSCANDO_CONDUCTOR'
    and v.conductor_id is null
    -- NUEVO: sin la cuota al dia la lista sale vacia.
    and (public.es_superadmin() or public.suscripcion_vigente(auth.uid()))
    -- Las mismas condiciones que `viajes_difusion_conductores`, repetidas aquí
    -- porque al ser `definer` la política ya no las aplica sola.
    and (
      public.es_superadmin()
      or (
        public.viaje_en_mi_zona(v.id)
        and (
          public.viaje_en_mi_celda(v.id)
          or (v.celdas_difusion is null and public.viaje_esta_cerca_de_mi(v.id))
        )
      )
    )
  -- Quien pidió antes no se queda al fondo de la lista.
  order by v.fecha_solicitud;
$$;

revoke execute on function public.solicitudes_abiertas() from public, anon;
grant execute on function public.solicitudes_abiertas() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Puerta 3: aceptar el viaje
-- ---------------------------------------------------------------------------
-- La que de verdad importa. Aunque alguien se salte las dos anteriores y llame
-- a `aceptar_viaje` a mano con el id de un viaje, aqui se queda.
-- Igual que arriba: cuerpo repetido, el anadido va marcado.

create or replace function public.aceptar_viaje(p_viaje_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_vehiculo uuid;
  v_ok uuid;
  v_categoria text;
  v_nombre text;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.profiles p
    join public.conductores c on c.id = p.id
    where p.id = v_uid
      and p.role in ('driver', 'superadmin')
      and p.activo
      and c.estado_aprobacion = 'aprobado'
      and c.disponible
  ) then
    raise exception 'Solo un conductor aprobado y disponible puede aceptar viajes'
      using errcode = 'check_violation';
  end if;

  -- NUEVO: la cuota mensual.
  if not public.suscripcion_vigente(v_uid) and not public.es_superadmin() then
    raise exception 'conductor_sin_suscripcion'
      using errcode = 'check_violation',
            hint = 'Paga la cuota mensual para poder recibir viajes';
  end if;

  select v.categoria into v_categoria
  from public.viajes v where v.id = p_viaje_id;

  select id into v_vehiculo
  from public.vehiculos
  where conductor_id = v_uid and activo and categoria = v_categoria
  limit 1;

  if v_vehiculo is null then
    select c.nombre into v_nombre
    from public.categorias_vehiculo c where c.id = v_categoria;

    raise exception 'Ese viaje pidio % y tu vehiculo en servicio no lo es',
      coalesce(v_nombre, v_categoria)
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.viajes
    where conductor_id = v_uid
      and estado not in ('FINALIZADO', 'CANCELADO', 'SIN_CONDUCTOR')
  ) then
    raise exception 'Ya tienes un viaje asignado' using errcode = 'check_violation';
  end if;

  if not (
    public.viaje_en_mi_celda(p_viaje_id)
    or public.viaje_esta_cerca_de_mi(p_viaje_id)
  ) then
    raise exception 'Ese viaje esta fuera de tu zona'
      using errcode = 'check_violation';
  end if;

  update public.viajes
  set estado = 'ACEPTADO', conductor_id = v_uid, vehiculo_id = v_vehiculo
  where id = p_viaje_id
    and estado = 'BUSCANDO_CONDUCTOR'
    and conductor_id is null
  returning id into v_ok;

  if v_ok is null then
    raise exception 'Ese viaje ya fue tomado por otro conductor'
      using errcode = 'check_violation';
  end if;

  return v_ok;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permisos
-- ---------------------------------------------------------------------------
-- El chofer LEE su suscripcion y nada mas. No hay politica de insert ni de
-- update a proposito: con RLS activo y sin politica, nadie escribe salvo la
-- service_role, que es justo lo que hace el webhook.

alter table public.suscripciones_chofer enable row level security;

drop policy if exists suscripciones_chofer_lee_el_suyo on public.suscripciones_chofer;
create policy suscripciones_chofer_lee_el_suyo
  on public.suscripciones_chofer
  for select
  to authenticated
  using (conductor_id = auth.uid() or public.es_superadmin());

-- `from public, anon`: quitarselo solo a `anon` no sirve de nada, porque `anon`
-- hereda de `public` y el permiso le vuelve a entrar por ahi.
revoke all on public.suscripciones_chofer from public, anon;
grant select on public.suscripciones_chofer to authenticated;

revoke execute on function public.suscripcion_vigente(uuid) from public, anon;
grant execute on function public.suscripcion_vigente(uuid) to authenticated;

revoke execute on function public.mi_suscripcion() from public, anon;
grant execute on function public.mi_suscripcion() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. El mes de arranque de los que ya estaban
-- ---------------------------------------------------------------------------
-- Los choferes que ya trabajaban no se enteran de esto por las buenas: si se
-- aplica la migracion sin mas, se quedan sin poder salir a la calle de un dia
-- para otro. Se les regala el primer mes.
--
-- `on conflict do nothing` sobre el indice de "una sola activa": volver a
-- correr la migracion no les regala otro mes.

insert into public.suscripciones_chofer
  (conductor_id, estado, vigente_hasta, proveedor, monto, moneda, datos)
select
  c.id,
  'activa',
  now() + interval '1 month',
  'cortesia',
  0,
  'USD',
  jsonb_build_object(
    'motivo', 'mes de arranque al activar el cobro',
    'aplicado_en', now()
  )
from public.conductores c
on conflict do nothing;

-- Una funcion de trigger no tiene por que estar en la API: PostgREST la expone
-- en /rest/v1/rpc/ solo por estar en `public`. Llamarla suelta fallaria igual
-- (no hay `new` fuera de un trigger), pero no hay razon para dejarla ofrecida.
-- Lo levanto el linter de Supabase despues de aplicar la migracion.
revoke execute on function public.conductor_disponible_con_cuota()
  from public, anon, authenticated;
