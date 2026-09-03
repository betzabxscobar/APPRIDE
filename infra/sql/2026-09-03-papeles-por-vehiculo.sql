-- Los papeles son del vehiculo, no del chofer
-- ------------------------------------------------------------------------
-- `documentos_conductor` tenia un unico por (conductor_id, tipo_documento).
-- Traducido: un chofer con dos autos tenia UNA matricula. La del segundo auto
-- no cabia en la tabla, y el que quisiera subirla pisaba la del primero.
--
-- Aqui se separa lo que es de la persona de lo que es del auto:
--
--   del chofer  -> cedula, licencia, foto de perfil
--   del vehiculo -> matricula, SPPAT, revision tecnica, foto del vehiculo
--
-- Y se añade lo que faltaba para que revisar signifique algo:
--
-- * **Caducidad.** Un SPPAT vencido valia igual que uno al dia, para siempre.
-- * **Numero.** Solo habia una foto; el numero de la poliza o de la matricula
--   no se guardaba en ningun lado, asi que no se podia cotejar con nada.
-- * **Motivo de rechazo.** Se rechazaba y el chofer no veia por que, asi que
--   volvia a subir exactamente lo mismo.
--
-- SOAT -> SPPAT: en Ecuador el SOAT lo reemplazo el SPPAT (Servicio Publico
-- para Pago de Accidentes de Transito). Las filas que ya existian se renombran.

-- 1. Columnas nuevas y tipos nuevos
-- ------------------------------------------------------------------------
alter table public.documentos_conductor
  add column if not exists vehiculo_id     uuid references public.vehiculos(id) on delete cascade,
  add column if not exists numero          text,
  add column if not exists caduca_el       date,
  add column if not exists motivo_rechazo  text,
  add column if not exists revisado_por    uuid references public.profiles(id),
  add column if not exists revisado_en     timestamptz;

comment on column public.documentos_conductor.vehiculo_id is
  'De que vehiculo es el papel. NULL en los de la persona: cedula, licencia y foto.';
comment on column public.documentos_conductor.caduca_el is
  'Hasta cuando vale. Un papel sin fecha no cuenta como vigente.';
comment on column public.documentos_conductor.motivo_rechazo is
  'Por que se rechazo, en palabras que lee el chofer. Sin esto vuelve a subir lo mismo.';

-- El `check` viejo solo conocia 'SOAT', asi que hay que soltarlo antes de
-- renombrar las filas: si no, la restriccion bloquea su propia migracion.
alter table public.documentos_conductor drop constraint if exists documentos_conductor_tipo_documento_check;

update public.documentos_conductor set tipo_documento = 'SPPAT'
 where tipo_documento = 'SOAT';

-- Los papeles de vehiculo que ya existian eran del auto en servicio: es el
-- unico que tenia el chofer cuando los subio.
update public.documentos_conductor d
   set vehiculo_id = v.id
  from public.vehiculos v
 where d.tipo_documento in ('matricula','SPPAT')
   and d.vehiculo_id is null
   and v.conductor_id = d.conductor_id
   and v.activo;

-- Si alguno quedo sin vehiculo al que atarse, es de un chofer que no tiene
-- ninguno: no describe nada y estorba a la restriccion de abajo.
delete from public.documentos_conductor
 where tipo_documento in ('matricula','SPPAT','revision_tecnica','foto_vehiculo')
   and vehiculo_id is null;

alter table public.documentos_conductor add constraint documentos_conductor_tipo_documento_check
  check (tipo_documento in
    ('cedula','licencia','foto_perfil',
     'matricula','SPPAT','revision_tecnica','foto_vehiculo'));

-- Cada papel en su sitio: el de la persona sin vehiculo, el del auto con el
-- suyo. Sin esto se podria subir una cedula «del vehiculo».
alter table public.documentos_conductor drop constraint if exists documentos_papel_en_su_sitio;
alter table public.documentos_conductor add constraint documentos_papel_en_su_sitio
  check (
    (tipo_documento in ('cedula','licencia','foto_perfil') and vehiculo_id is null)
    or
    (tipo_documento in ('matricula','SPPAT','revision_tecnica','foto_vehiculo')
     and vehiculo_id is not null)
  );

-- Un rechazo sin motivo no sirve de nada.
alter table public.documentos_conductor drop constraint if exists documentos_rechazo_con_motivo;
alter table public.documentos_conductor add constraint documentos_rechazo_con_motivo
  check (estado <> 'rechazado' or coalesce(trim(motivo_rechazo), '') <> '');

-- 2. Los indices unicos
-- ------------------------------------------------------------------------
-- El de antes hacia imposible el segundo vehiculo. Se parte en dos.
-- El indice se llama `documentos_conductor_tipo_unico`, no como lo bautizaria
-- Postgres por su cuenta. Se listan los dos nombres porque el segundo es el
-- que sale si algun dia la tabla se recrea desde cero.
drop index if exists public.documentos_conductor_tipo_unico;
drop index if exists public.documentos_conductor_conductor_id_tipo_documento_key;
alter table public.documentos_conductor
  drop constraint if exists documentos_conductor_conductor_id_tipo_documento_key;

create unique index if not exists documentos_del_chofer_unico
  on public.documentos_conductor (conductor_id, tipo_documento)
  where vehiculo_id is null;

create unique index if not exists documentos_del_vehiculo_unico
  on public.documentos_conductor (vehiculo_id, tipo_documento)
  where vehiculo_id is not null;

-- 3. Subir un papel
-- ------------------------------------------------------------------------
-- Las tres cambian de firma. `create or replace` con un parametro de mas no
-- reemplaza: crea una segunda funcion con el mismo nombre, y entonces una
-- llamada con los argumentos viejos queda ambigua o cae en la version vieja,
-- que es justo la que no valida. Hay que borrar la anterior.
drop function if exists public.registrar_documento(text, text);
drop function if exists public.revisar_documento(uuid, boolean);
drop function if exists public.revisar_conductor(uuid, boolean);

create or replace function public.registrar_documento(
  p_tipo text,
  p_url text,
  p_vehiculo_id uuid default null,
  p_numero text default null,
  p_caduca_el date default null)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_del_vehiculo boolean;
  v_caduca boolean;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  if p_tipo not in ('cedula','licencia','foto_perfil',
                    'matricula','SPPAT','revision_tecnica','foto_vehiculo') then
    raise exception 'Tipo de documento no valido' using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_url), '') = '' then
    raise exception 'Falta el archivo' using errcode = 'check_violation';
  end if;

  v_del_vehiculo := p_tipo in ('matricula','SPPAT','revision_tecnica','foto_vehiculo');
  -- Una foto no caduca; los papeles si.
  v_caduca := p_tipo in ('matricula','SPPAT','revision_tecnica');

  if v_del_vehiculo then
    if p_vehiculo_id is null then
      raise exception 'Ese papel es de un vehiculo: dinos de cual'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.vehiculos
                   where id = p_vehiculo_id and conductor_id = v_uid) then
      raise exception 'Ese vehiculo no es tuyo' using errcode = '42501';
    end if;
  elsif p_vehiculo_id is not null then
    raise exception 'Ese papel es tuyo, no de un vehiculo'
      using errcode = 'check_violation';
  end if;

  if v_caduca and (p_caduca_el is null or p_caduca_el <= current_date) then
    raise exception 'Ese documento necesita una fecha de caducidad que no haya pasado'
      using errcode = 'check_violation';
  end if;

  insert into public.conductores (id) values (v_uid) on conflict do nothing;

  -- Volver a subir es volver a la cola: se borra la revision anterior y el
  -- motivo por el que se habia rechazado.
  if v_del_vehiculo then
    insert into public.documentos_conductor
      (conductor_id, vehiculo_id, tipo_documento, url_archivo, numero, caduca_el, estado)
    values (v_uid, p_vehiculo_id, p_tipo, trim(p_url),
            nullif(trim(coalesce(p_numero, '')), ''), p_caduca_el, 'pendiente')
    on conflict (vehiculo_id, tipo_documento) where vehiculo_id is not null
    do update set url_archivo = excluded.url_archivo,
                  numero = excluded.numero,
                  caduca_el = excluded.caduca_el,
                  estado = 'pendiente',
                  motivo_rechazo = null,
                  revisado_por = null,
                  revisado_en = null,
                  fecha_subida = now()
    returning id into v_id;
  else
    insert into public.documentos_conductor
      (conductor_id, tipo_documento, url_archivo, numero, caduca_el, estado)
    values (v_uid, p_tipo, trim(p_url),
            nullif(trim(coalesce(p_numero, '')), ''), p_caduca_el, 'pendiente')
    on conflict (conductor_id, tipo_documento) where vehiculo_id is null
    do update set url_archivo = excluded.url_archivo,
                  numero = excluded.numero,
                  caduca_el = excluded.caduca_el,
                  estado = 'pendiente',
                  motivo_rechazo = null,
                  revisado_por = null,
                  revisado_en = null,
                  fecha_subida = now()
    returning id into v_id;
  end if;

  return v_id;
end;
$function$;

-- 4. Revisar un papel, con motivo
-- ------------------------------------------------------------------------
create or replace function public.revisar_documento(
  p_documento_id uuid, p_aprobado boolean, p_motivo text default null)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  if not public.es_administrativo() then
    raise exception 'Solo la administracion revisa documentos' using errcode = '42501';
  end if;

  if not p_aprobado and v_motivo is null then
    raise exception 'Un rechazo necesita un motivo: es lo unico que el chofer va a leer'
      using errcode = 'check_violation';
  end if;

  update public.documentos_conductor
  set estado = case when p_aprobado then 'aprobado' else 'rechazado' end,
      motivo_rechazo = case when p_aprobado then null else v_motivo end,
      revisado_por = auth.uid(),
      revisado_en = now()
  where id = p_documento_id;

  if not found then
    raise exception 'Ese documento no existe' using errcode = 'no_data_found';
  end if;

  return case when p_aprobado then 'aprobado' else 'rechazado' end;
end;
$function$;

-- 5. Que falta, dicho en una lista
-- ------------------------------------------------------------------------
-- Las usan la pantalla del chofer, la de revision y las propias funciones que
-- aprueban. Una sola definicion de «esta completo», en vez de tres que se
-- desincronizan.
create or replace function public.papeles_que_faltan_vehiculo(p_vehiculo_id uuid)
 returns text[] language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_falta text[];
begin
  -- Rebota en vez de devolver una lista vacia. La funcion es `definer` y se
  -- salta RLS; una lista vacia significa «esta completo», que es la respuesta
  -- mas peligrosa que se le puede dar a quien no deberia estar preguntando.
  if not exists (
    select 1 from public.vehiculos v
    where v.id = p_vehiculo_id
      and (v.conductor_id = auth.uid() or public.es_administrativo())
  ) then
    raise exception 'Ese vehiculo no es tuyo' using errcode = '42501';
  end if;

  select coalesce(array_agg(t.tipo order by t.tipo), '{}')
  into v_falta
  from unnest(array['matricula','SPPAT','revision_tecnica','foto_vehiculo']) as t(tipo)
  where not exists (
    select 1 from public.documentos_conductor d
    where d.vehiculo_id = p_vehiculo_id
      and d.tipo_documento = t.tipo
      and d.estado = 'aprobado'
      -- La foto no caduca; los otros tres si.
      and (t.tipo = 'foto_vehiculo'
           or (d.caduca_el is not null and d.caduca_el >= current_date)));

  return v_falta;
end;
$function$;

create or replace function public.papeles_que_faltan_chofer(p_conductor_id uuid default null)
 returns text[] language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_id uuid := coalesce(p_conductor_id, auth.uid());
  v_falta text[] := '{}';
  v_c public.conductores%rowtype;
begin
  if v_id is null then return array['identidad']; end if;
  if v_id <> auth.uid() and not public.es_administrativo() then
    raise exception 'No tienes permiso para ver eso' using errcode = '42501';
  end if;

  select * into v_c from public.conductores where id = v_id;
  if v_c.id is null then return array['identidad']; end if;

  if v_c.cedula is null or v_c.codigo_dactilar is null or v_c.licencia_tipo is null then
    v_falta := v_falta || 'identidad'::text;
  end if;
  if v_c.licencia_caduca_el is null or v_c.licencia_caduca_el < current_date then
    v_falta := v_falta || 'licencia_vigente'::text;
  end if;

  v_falta := v_falta || coalesce((
    select array_agg(t.tipo order by t.tipo)
    from unnest(array['cedula','licencia','foto_perfil']) as t(tipo)
    where not exists (
      select 1 from public.documentos_conductor d
      where d.conductor_id = v_id
        and d.vehiculo_id is null
        and d.tipo_documento = t.tipo
        and d.estado = 'aprobado')), '{}');

  -- Y al menos un vehiculo entero, con la licencia que le corresponde.
  if not exists (
    select 1 from public.vehiculos v
    where v.conductor_id = v_id
      and public.papeles_que_faltan_vehiculo(v.id) = '{}'
      and public.licencia_habilita(v_c.licencia_tipo, v.categoria)
  ) then
    v_falta := v_falta || 'vehiculo_completo'::text;
  end if;

  return v_falta;
end;
$function$;

-- 6. Activar un vehiculo: papeles al dia y la licencia que toca
-- ------------------------------------------------------------------------
create or replace function public.activar_vehiculo(p_vehiculo_id uuid)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_categoria text;
  v_licencia text;
  v_falta text[];
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  select categoria into v_categoria from public.vehiculos
  where id = p_vehiculo_id and conductor_id = v_uid;

  if v_categoria is null then
    raise exception 'Ese vehiculo no es tuyo' using errcode = '42501';
  end if;

  select licencia_tipo into v_licencia from public.conductores where id = v_uid;

  if not public.licencia_habilita(v_licencia, v_categoria) then
    raise exception 'Tu licencia % no habilita para conducir un vehiculo de categoria %',
      coalesce(v_licencia, 'sin registrar'), v_categoria
      using errcode = 'check_violation';
  end if;

  v_falta := public.papeles_que_faltan_vehiculo(p_vehiculo_id);
  if v_falta <> '{}' then
    raise exception 'A ese vehiculo le faltan papeles aprobados y vigentes: %',
      array_to_string(v_falta, ', ') using errcode = 'check_violation';
  end if;

  update public.vehiculos set activo = false
   where conductor_id = v_uid and activo and id <> p_vehiculo_id;
  update public.vehiculos set activo = true where id = p_vehiculo_id;
end;
$function$;

-- 7. Aprobar a un chofer: la misma lista, sin excepciones
-- ------------------------------------------------------------------------
create or replace function public.revisar_conductor(
  p_conductor_id uuid, p_aprobado boolean, p_motivo text default null)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare
  v_falta text[];
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  if not public.es_administrativo() then
    raise exception 'Solo la administracion aprueba conductores' using errcode = '42501';
  end if;

  if not p_aprobado then
    if v_motivo is null then
      raise exception 'Un rechazo necesita un motivo' using errcode = 'check_violation';
    end if;
    update public.conductores
    set estado_aprobacion = 'rechazado' where id = p_conductor_id;
    return 'rechazado';
  end if;

  v_falta := public.papeles_que_faltan_chofer(p_conductor_id);
  if v_falta <> '{}' then
    raise exception 'Todavia falta: %', array_to_string(v_falta, ', ')
      using errcode = 'check_violation';
  end if;

  update public.conductores
  set estado_aprobacion = 'aprobado' where id = p_conductor_id;

  return 'aprobado';
end;
$function$;

-- 8. Ponerse en linea: tambien se comprueba al conectarse
-- ------------------------------------------------------------------------
-- Aprobar es de una vez; los papeles caducan solos. Un chofer aprobado en
-- enero con el SPPAT vencido en marzo no puede seguir trabajando en abril, y
-- eso solo se ve mirando en el momento de conectarse.
create or replace function public.validar_disponibilidad_conductor_real()
 returns trigger language plpgsql set search_path to ''
as $function$
declare
  v_saldo numeric;
  v_licencia_caduca date;
  v_activo uuid;
  v_falta text[];
begin
  if new.disponible and not exists (
    select 1 from public.profiles p
    where p.id = new.id and p.role in ('driver', 'superadmin')
  ) then
    raise exception 'Solo una cuenta con rol conductor puede ponerse disponible'
      using errcode = 'check_violation';
  end if;

  if new.disponible then
    select coalesce(sum(m.monto), 0) into v_saldo
    from public.movimientos_chofer m where m.conductor_id = new.id;

    if v_saldo < -public.limite_deuda_chofer() then
      raise exception 'Tienes % en comisiones pendientes. Liquida para volver a conectarte.',
        to_char(-v_saldo, 'FM999990.00') using errcode = 'check_violation';
    end if;

    select licencia_caduca_el into v_licencia_caduca
    from public.conductores where id = new.id;

    if v_licencia_caduca is null or v_licencia_caduca < current_date then
      raise exception 'Tu licencia esta vencida. Sube la nueva para volver a conectarte.'
        using errcode = 'check_violation';
    end if;

    select id into v_activo from public.vehiculos
    where conductor_id = new.id and activo;

    if v_activo is null then
      raise exception 'No tienes ningun vehiculo en servicio'
        using errcode = 'check_violation';
    end if;

    v_falta := public.papeles_que_faltan_vehiculo(v_activo);
    if v_falta <> '{}' then
      raise exception 'A tu vehiculo le faltan papeles al dia: %',
        array_to_string(v_falta, ', ') using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$function$;

-- 9. Registrar un vehiculo que la licencia no habilita
-- ------------------------------------------------------------------------
-- Se avisa ya al registrarlo, no al activarlo: enterarse tres pantallas
-- despues de que tu licencia no sirve para ese auto es perder el tiempo de
-- alguien. Si todavia no hay licencia registrada, se deja pasar: el orden en
-- que suba las cosas es asunto suyo.
create or replace function public.validar_licencia_del_vehiculo()
 returns trigger language plpgsql set search_path to ''
as $function$
declare
  v_licencia text;
begin
  select licencia_tipo into v_licencia
  from public.conductores where id = new.conductor_id;

  if v_licencia is not null and not public.licencia_habilita(v_licencia, new.categoria) then
    raise exception 'Tu licencia % no habilita para un vehiculo de categoria %',
      v_licencia, new.categoria using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

drop trigger if exists vehiculos_licencia_habilitante on public.vehiculos;
create trigger vehiculos_licencia_habilitante
  before insert or update of categoria on public.vehiculos
  for each row execute function public.validar_licencia_del_vehiculo();

-- 10. La vista de revision, con lo nuevo
-- ------------------------------------------------------------------------
-- `create or replace view` solo deja añadir columnas al final: cambiar el
-- orden obliga a borrar la vista y con ella todo lo que dependa. Por eso las
-- cuatro nuevas van detras, aunque leidas se lean raro.
--
-- `papeles_que_faltan` viene de la misma funcion que usa `revisar_conductor`,
-- a proposito: la pantalla de revision no puede decir «esta completo» si la
-- funcion que aprueba piensa lo contrario.
create or replace view public.conductores_revision
with (security_invoker = on) as
select c.id,
  p.full_name as nombre, p.email, p.phone as telefono, p.foto_url,
  c.estado_aprobacion, c.disponible, c.calificacion_promedio, c.fecha_aprobacion,
  c.created_at as fecha_registro,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', v.id, 'placa', v.placa, 'marca', v.marca, 'modelo', v.modelo,
      'anio', v.anio, 'color', v.color, 'activo', v.activo, 'categoria', v.categoria)
      order by v.activo desc, v.created_at)
    from public.vehiculos v where v.conductor_id = c.id), '[]'::jsonb) as vehiculos,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'tipo_documento', d.tipo_documento, 'estado', d.estado,
      'url_archivo', d.url_archivo, 'fecha_subida', d.fecha_subida,
      'vehiculo_id', d.vehiculo_id, 'numero', d.numero,
      'caduca_el', d.caduca_el, 'motivo_rechazo', d.motivo_rechazo)
      order by d.tipo_documento)
    from public.documentos_conductor d where d.conductor_id = c.id), '[]'::jsonb) as documentos,
  (select count(*) from public.documentos_conductor d
    where d.conductor_id = c.id and d.estado = 'aprobado') as documentos_aprobados,
  (select count(*) from public.documentos_conductor d
    where d.conductor_id = c.id and d.estado = 'pendiente') as documentos_pendientes,
  c.cedula, c.codigo_dactilar, c.licencia_tipo, c.licencia_caduca_el,
  public.papeles_que_faltan_chofer(c.id) as papeles_que_faltan
from public.conductores c
join public.profiles p on p.id = c.id;

-- La vista es `security_invoker`, asi que RLS ya la protege; el `grant` a anon
-- que traia de fabrica no aportaba nada y contradecia la regla del proyecto.
revoke all on public.conductores_revision from anon;

-- Permisos
-- ------------------------------------------------------------------------
revoke execute on function public.registrar_documento(text, text, uuid, text, date) from anon, public;
revoke execute on function public.revisar_documento(uuid, boolean, text) from anon, public;
revoke execute on function public.revisar_conductor(uuid, boolean, text) from anon, public;
revoke execute on function public.papeles_que_faltan_vehiculo(uuid) from anon, public;
revoke execute on function public.papeles_que_faltan_chofer(uuid) from anon, public;
grant execute on function public.registrar_documento(text, text, uuid, text, date) to authenticated;
grant execute on function public.revisar_documento(uuid, boolean, text) to authenticated;
grant execute on function public.revisar_conductor(uuid, boolean, text) to authenticated;
grant execute on function public.papeles_que_faltan_vehiculo(uuid) to authenticated;
grant execute on function public.papeles_que_faltan_chofer(uuid) to authenticated;


-- Comprobacion
-- ------------------------------------------------------------------------
--   select public.papeles_que_faltan_chofer('<chofer>');
--     -> {identidad, licencia_vigente, foto_perfil, vehiculo_completo}
--   select public.activar_vehiculo('<vehiculo sin papeles>');  -- rebota
--   select public.revisar_conductor('<chofer>', true);         -- rebota con la lista
--
-- Y con dos vehiculos, cada uno tiene que poder tener su propia matricula:
--   select vehiculo_id, tipo_documento from public.documentos_conductor
--    where conductor_id = '<chofer>' order by vehiculo_id;
