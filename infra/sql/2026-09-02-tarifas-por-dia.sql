-- Las franjas pico, solo de lunes a viernes
-- ------------------------------------------------------------------------
-- El Pico y Placa de Quito no rige el fin de semana, pero `tarifas` no
-- distinguia el dia: un domingo a las 17:00 se cobraba hora pico con la
-- ciudad vacia.
--
-- `dias` es un arreglo de dias ISO —1 lunes .. 7 domingo— y NULL significa
-- «todos los dias», que es como se quedan la estandar y la nocturna.

alter table public.tarifas
  add column if not exists dias smallint[];

comment on column public.tarifas.dias is
  'Dias ISO (1=lunes .. 7=domingo) en que aplica la franja. NULL = todos los '
  'dias. Ojo con las franjas que cruzan medianoche: a la 01:00 del sabado el '
  'dia ya es sabado, asi que una nocturna limitada a {1,2,3,4,5} dejaria de '
  'aplicar a mitad de la madrugada del viernes. Por eso la nocturna va en NULL.';

update public.tarifas
set dias = '{1,2,3,4,5}'::smallint[]
where nombre in ('Tarifa Hora Pico Manana', 'Tarifa Hora Pico Tarde');

create or replace function public.tarifa_vigente()
 returns uuid
 language sql
 stable
 set search_path to ''
as $function$
  with ahora as (
    select extract(hour   from (now() at time zone 'America/Guayaquil'))::int as hora,
           extract(isodow from (now() at time zone 'America/Guayaquil'))::int as dia
  )
  select t.id
  from public.tarifas t, ahora a
  where t.activo
    and t.hora_desde is not null
    -- NULL en `dias` es «todos los dias».
    and (t.dias is null or a.dia = any(t.dias))
    and (
      -- Franja que no cruza medianoche (06:00-08:59)
      (t.hora_desde <= t.hora_hasta and a.hora between t.hora_desde and t.hora_hasta)
      -- Franja que si la cruza (22:00-04:59)
      or (t.hora_desde > t.hora_hasta and (a.hora >= t.hora_desde or a.hora <= t.hora_hasta))
    )
  order by t.tarifa_base desc
  limit 1;
$function$;


-- Comprobacion
-- ------------------------------------------------------------------------
-- Horas por franja en una semana. Debe dar 15 pico manana (3 x 5 dias),
-- 20 pico tarde (4 x 5), 49 nocturna (7 x 7) y 84 estandar. Total 168.
--
--   with g as (
--     select d.dia, h.hora, coalesce((
--       select t.nombre from public.tarifas t
--       where t.activo and t.hora_desde is not null
--         and (t.dias is null or d.dia = any(t.dias))
--         and ((t.hora_desde <= t.hora_hasta and h.hora between t.hora_desde and t.hora_hasta)
--           or (t.hora_desde >  t.hora_hasta and (h.hora >= t.hora_desde or h.hora <= t.hora_hasta)))
--       order by t.tarifa_base desc limit 1
--     ), 'Tarifa Estandar') as franja
--     from generate_series(1,7) as d(dia), generate_series(0,23) as h(hora)
--   )
--   select franja, count(*) from g group by franja order by franja;
