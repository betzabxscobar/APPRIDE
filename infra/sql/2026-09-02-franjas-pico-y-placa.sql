-- Franjas horarias según el Pico y Placa de Quito
-- ------------------------------------------------------------------------
-- Dos problemas, uno de datos y otro de fuente.
--
-- 1. `tarifa_vigente()` compara con `between` sobre la hora entera, y los dos
--    extremos entran. Con `hora_hasta = 9`, la hora 9 contaba completa: la
--    "hora pico 06:00-09:00" cobraba hasta las 09:59, y la "nocturna
--    22:00-05:00" hasta las 05:59. Una hora de más cada una.
--
-- 2. La franja de la mañana estaba inventada y la de la tarde no existía. El
--    Pico y Placa de Quito —la definición municipal de cuándo hay congestión—
--    es 06:00-09:30 y 16:00-20:00, de lunes a viernes. En Quito la tarde es
--    la peor, y no se estaba cobrando.
--
-- Como la tabla guarda horas enteras, las medias horas se redondean. En la
-- mañana se recorta (06:00-08:59) en vez de estirar: cobrar hora pico a las
-- 09:45 es cobrar de más fuera de la congestión. En la tarde el redondeo
-- clava el horario (16:00-19:59).
--
-- PENDIENTE: el Pico y Placa es de lunes a viernes y `tarifas` no tiene
-- columna de día, así que un domingo a las 17:00 se cobra hora pico igual.
-- Arreglarlo pide una columna nueva y tocar `tarifa_vigente()`.

-- La mañana: 06:00-08:59. Se renombra porque ya no es la única franja pico.
update public.tarifas
set nombre = 'Tarifa Hora Pico Manana', hora_desde = 6, hora_hasta = 8
where nombre = 'Tarifa Hora Pico';

-- La nocturna decía 05:00 y llegaba hasta las 05:59.
update public.tarifas
set hora_hasta = 4
where nombre = 'Tarifa Nocturna';

-- La tarde no existía. Mismos precios que la mañana.
insert into public.tarifas
  (nombre, tarifa_base, costo_por_km, costo_por_minuto, carrera_minima,
   porcentaje_conductor, activo, hora_desde, hora_hasta)
select 'Tarifa Hora Pico Tarde', 0.49, 0.35, 0.10, 1.40, 0.85, true, 16, 19
where not exists (
  select 1 from public.tarifas where nombre = 'Tarifa Hora Pico Tarde'
);


-- Comprobación
-- ------------------------------------------------------------------------
-- Qué franja cae en cada hora del día. Debe dar: 00-04 nocturna, 05 estándar,
-- 06-08 pico mañana, 09-15 estándar, 16-19 pico tarde, 20-21 estándar,
-- 22-23 nocturna.
--
--   select h.hora, coalesce((
--     select t.nombre from public.tarifas t
--     where t.activo and t.hora_desde is not null
--       and ((t.hora_desde <= t.hora_hasta and h.hora between t.hora_desde and t.hora_hasta)
--         or (t.hora_desde >  t.hora_hasta and (h.hora >= t.hora_desde or h.hora <= t.hora_hasta)))
--     order by t.tarifa_base desc limit 1
--   ), 'Tarifa Estandar')
--   from generate_series(0,23) as h(hora) order by h.hora;
