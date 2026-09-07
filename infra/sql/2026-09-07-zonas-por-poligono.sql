-- Zonas de trabajo del chofer, por polígono
-- ---------------------------------------------------------------------------
-- El chofer elige en qué zonas de Quito trabaja y solo le llegan solicitudes
-- que salen de ellas, y solo mientras él está dentro. Las dos condiciones son
-- necesarias: la primera para que no le ofrezcan carreras al otro extremo de
-- la ciudad, y la segunda para que un chofer que hoy anda por el valle no
-- acapare las solicitudes del norte solo por tenerlo marcado.
--
-- SOBRE LOS LÍMITES: los polígonos que se siembran aquí son **aproximados**.
-- Están dibujados a ojo sobre la geografía de Quito para que el sistema arranque
-- funcionando, no calcados de la división administrativa del Municipio. Se
-- corrigen editando la fila, sin tocar código: por eso el área vive en una tabla
-- y no escrita en una función.
--
-- Un chofer sin zonas marcadas NO se queda sin trabajo: sigue recibiendo como
-- antes. La zona es algo que se activa, no un requisito nuevo que deje a nadie
-- fuera de la noche a la mañana.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. Las zonas
-- ---------------------------------------------------------------------------
create table if not exists public.zonas (
  id text primary key,
  nombre text not null,
  area extensions.geography(Polygon, 4326) not null,
  activa boolean not null default true,
  orden smallint not null default 0
);

create index if not exists zonas_area_idx on public.zonas using gist (area);

-- Quito se estira de norte a sur en el valle, y los dos valles quedan al este
-- y al sureste. Los rangos son de latitud/longitud porque es lo que se puede
-- ajustar sin herramientas: cuando haya el trazado real del Municipio, se
-- reemplaza el POLYGON y ya.
insert into public.zonas (id, nombre, area, orden) values
  -- Quito Norte no es un rectangulo: al norte de -0.14 la ciudad se estrecha y
  -- lo que queda al este ya es Calderon. De ahi la forma de L.
  ('quito_norte', 'Quito Norte',
   extensions.ST_GeogFromText('POLYGON((-78.56 -0.19, -78.44 -0.19, -78.44 -0.14, -78.46 -0.14, -78.46 -0.05, -78.56 -0.05, -78.56 -0.19))'), 1),
  ('quito_centro', 'Quito Centro',
   extensions.ST_GeogFromText('POLYGON((-78.56 -0.25, -78.44 -0.25, -78.44 -0.19, -78.56 -0.19, -78.56 -0.25))'), 2),
  ('quito_sur', 'Quito Sur',
   extensions.ST_GeogFromText('POLYGON((-78.60 -0.40, -78.47 -0.40, -78.47 -0.25, -78.60 -0.25, -78.60 -0.40))'), 3),
  ('calderon', 'Calderón y Carapungo',
   extensions.ST_GeogFromText('POLYGON((-78.46 -0.14, -78.36 -0.14, -78.36 -0.02, -78.46 -0.02, -78.46 -0.14))'), 4),
  ('cumbaya_tumbaco', 'Cumbayá y Tumbaco',
   extensions.ST_GeogFromText('POLYGON((-78.44 -0.26, -78.30 -0.26, -78.30 -0.15, -78.44 -0.15, -78.44 -0.26))'), 5),
  ('los_chillos', 'Valle de los Chillos',
   extensions.ST_GeogFromText('POLYGON((-78.47 -0.40, -78.36 -0.40, -78.36 -0.26, -78.47 -0.26, -78.47 -0.40))'), 6)
on conflict (id) do update
  set nombre = excluded.nombre,
      area   = excluded.area,
      orden  = excluded.orden;

alter table public.zonas enable row level security;

drop policy if exists zonas_lectura on public.zonas;
create policy zonas_lectura on public.zonas
  for select to authenticated using (activa);


-- 2. En qué zonas trabaja cada chofer
-- ---------------------------------------------------------------------------
create table if not exists public.zonas_conductor (
  conductor_id uuid not null references public.conductores(id) on delete cascade,
  zona_id text not null references public.zonas(id) on delete cascade,
  primary key (conductor_id, zona_id)
);

alter table public.zonas_conductor enable row level security;

drop policy if exists zonas_conductor_propias on public.zonas_conductor;
create policy zonas_conductor_propias on public.zonas_conductor
  for all to authenticated
  using (conductor_id = (select auth.uid()) or public.es_administrativo())
  with check (conductor_id = (select auth.uid()));


-- 3. En qué zona cae un punto
-- ---------------------------------------------------------------------------
-- `ST_Covers` y no `ST_Within` porque el borde cuenta como dentro: quien está
-- justo en la línea de la avenida que separa dos zonas tiene que caer en una,
-- no en ninguna.
create or replace function public.zona_de(p_lat double precision, p_lng double precision)
returns text language sql stable set search_path = ''
as $$
  select z.id
  from public.zonas z
  where z.activa
    and extensions.ST_Covers(
          z.area,
          extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography)
  order by z.orden
  limit 1;
$$;


-- 4. Las zonas del chofer
-- ---------------------------------------------------------------------------
create or replace function public.mis_zonas()
returns table (id text, nombre text, elegida boolean)
language sql stable security definer set search_path = ''
as $$
  select z.id, z.nombre,
         exists (select 1 from public.zonas_conductor zc
                 where zc.zona_id = z.id and zc.conductor_id = (select auth.uid()))
  from public.zonas z
  where z.activa
  order by z.orden;
$$;

create or replace function public.elegir_mis_zonas(p_zonas text[])
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_n integer;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  if not exists (select 1 from public.conductores where id = v_uid) then
    raise exception 'Solo un chofer elige zonas' using errcode = '42501';
  end if;

  if p_zonas is not null and exists (
    select 1 from unnest(p_zonas) z(id)
    where not exists (select 1 from public.zonas where zonas.id = z.id and activa)
  ) then
    raise exception 'Alguna de esas zonas no existe' using errcode = 'check_violation';
  end if;

  delete from public.zonas_conductor where conductor_id = v_uid;

  insert into public.zonas_conductor (conductor_id, zona_id)
  select v_uid, z.id from unnest(coalesce(p_zonas, '{}')) z(id)
  on conflict do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;


-- 5. La regla: su zona, y él dentro de ella
-- ---------------------------------------------------------------------------
-- Un chofer sin zonas marcadas pasa siempre: la zona se activa, no se impone.
create or replace function public.viaje_en_mi_zona(p_viaje_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select
    not exists (
      select 1 from public.zonas_conductor
      where conductor_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.zonas_conductor zc
      join public.zonas z on z.id = zc.zona_id and z.activa
      join public.conductores c on c.id = zc.conductor_id
      join public.ubicaciones o
        on o.viaje_id = p_viaje_id and o.tipo = 'origen'
      where zc.conductor_id = (select auth.uid())
        and c.ultima_posicion is not null
        -- El chofer, ahora mismo, dentro de la zona.
        and extensions.ST_Covers(z.area, c.ultima_posicion)
        -- Y el viaje saliendo de esa misma zona.
        and extensions.ST_Covers(
              z.area,
              extensions.ST_SetSRID(
                extensions.ST_MakePoint(o.longitud, o.latitud), 4326
              )::extensions.geography)
    );
$$;

-- La difusión ahora pasa además por la zona. Lo demás no cambia: sigue
-- exigiendo estar disponible, aprobado y con posición reciente.
drop policy if exists viajes_difusion_conductores on public.viajes;
create policy viajes_difusion_conductores on public.viajes
  for select to authenticated
  using (
    estado = 'BUSCANDO_CONDUCTOR'
    and conductor_id is null
    and (
      public.es_superadmin()
      or (
        public.viaje_en_mi_zona(id)
        and (
          public.viaje_en_mi_celda(id)
          or (celdas_difusion is null and public.viaje_esta_cerca_de_mi(id))
        )
      )
    )
  );


-- 6. Lo que la app necesita para enseñar una oportunidad de verdad
-- ---------------------------------------------------------------------------
-- Hasta ahora la pantalla del chofer inventaba las tarjetas. Para llenarlas con
-- datos reales hacen falta tres cosas que la vista no daba: lo que gana él, los
-- kilómetros y los minutos.
--
-- El `with (security_invoker = on)` NO se puede omitir: sin él la vista corre
-- como su dueño y se salta el RLS de `viajes`.
create or replace view public.viajes_detalle
with (security_invoker = on) as
 SELECT v.id,
    v.estado,
    v.pasajero_id,
    v.conductor_id,
    v.vehiculo_id,
    v.tarifa_estimada,
    v.tarifa_final,
    v.fecha_solicitud,
    v.fecha_inicio,
    v.fecha_fin,
    t.nombre AS tarifa_nombre,
    pp.full_name AS pasajero_nombre,
    pp.phone AS pasajero_telefono,
        CASE
            WHEN v.conductor_id IS NULL THEN NULL::text
            ELSE COALESCE(NULLIF(TRIM(BOTH FROM pc.full_name), ''::text), pc.email, 'Conductor asignado'::text)
        END AS conductor_nombre,
    pc.phone AS conductor_telefono,
    c.calificacion_promedio AS conductor_calificacion,
    ve.placa AS vehiculo_placa,
    ve.marca AS vehiculo_marca,
    ve.modelo AS vehiculo_modelo,
    ve.color AS vehiculo_color,
    o.latitud AS origen_lat,
    o.longitud AS origen_lng,
    o.direccion_texto AS origen_texto,
    d.latitud AS destino_lat,
    d.longitud AS destino_lng,
    d.direccion_texto AS destino_texto,
    COALESCE(cobro.monto_cobrado, 0::numeric) AS monto_cobrado,
    cobro.estado AS pago_estado,
    o.referencia AS origen_referencia,
    d.referencia AS destino_referencia,
    v.categoria,
    cat.nombre AS categoria_nombre,
    cat.icono AS categoria_icono,
    v.cancelado_por,
    v.cancelado_en,
    v.motivo_cancelacion,
    v.distancia_recorrida_km,
    v.llegada_verificada,
    v.desvio_detectado,
    COALESCE(cobro.multa, 0::numeric) AS multa,
    -- Lo que se lleva el chofer de este viaje, con el porcentaje de SU tarifa.
    round(COALESCE(v.tarifa_final, v.tarifa_estimada) * t.porcentaje_conductor, 2)
      AS gana_conductor,
    -- Línea recta origen-destino. No es la ruta, y no pretende serlo: sirve
    -- para que el chofer se haga una idea antes de aceptar.
    round(public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)::numeric, 1)
      AS distancia_km,
    greatest(1, round(
      public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)
      / public.velocidad_media_kmh() * 60
    )::integer) AS minutos_estimados,
    public.zona_de(o.latitud, o.longitud) AS zona_origen
   FROM viajes v
     JOIN tarifas t ON t.id = v.tarifa_id
     JOIN profiles pp ON pp.id = v.pasajero_id
     LEFT JOIN categorias_vehiculo cat ON cat.id = v.categoria
     LEFT JOIN profiles pc ON pc.id = v.conductor_id
     LEFT JOIN conductores c ON c.id = v.conductor_id
     LEFT JOIN vehiculos ve ON ve.id = v.vehiculo_id
     LEFT JOIN ubicaciones o ON o.viaje_id = v.id AND o.tipo = 'origen'::text
     LEFT JOIN ubicaciones d ON d.viaje_id = v.id AND d.tipo = 'destino'::text
     LEFT JOIN LATERAL ( SELECT sum(
                CASE
                    WHEN p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text, 'multa'::text])) THEN p.monto
                    WHEN p.estado = 'completado'::text AND p.tipo = 'reembolso'::text THEN - p.monto
                    ELSE 0::numeric
                END) AS monto_cobrado,
                sum(
                CASE
                    WHEN p.tipo = 'multa'::text THEN p.monto
                    ELSE 0::numeric
                END) AS multa,
                CASE
                    WHEN bool_or(p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text, 'multa'::text]))) THEN 'completado'::text
                    WHEN bool_or(p.estado = 'pendiente'::text) THEN 'pendiente'::text
                    WHEN count(*) > 0 THEN 'fallido'::text
                    ELSE NULL::text
                END AS estado
           FROM pagos p
          WHERE p.viaje_id = v.id) cobro ON true;

alter view public.viajes_detalle set (security_invoker = on);


-- 7. Permisos
-- ---------------------------------------------------------------------------
revoke execute on function public.zona_de(double precision, double precision) from public, anon;
revoke execute on function public.mis_zonas() from public, anon;
revoke execute on function public.elegir_mis_zonas(text[]) from public, anon;
revoke execute on function public.viaje_en_mi_zona(uuid) from public, anon;

grant execute on function public.zona_de(double precision, double precision) to authenticated;
grant execute on function public.mis_zonas() to authenticated;
grant execute on function public.elegir_mis_zonas(text[]) to authenticated;
grant execute on function public.viaje_en_mi_zona(uuid) to authenticated;

grant select on public.zonas to authenticated;
grant select, insert, update, delete on public.zonas_conductor to authenticated;
