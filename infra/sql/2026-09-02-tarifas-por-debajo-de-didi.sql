-- Por debajo de DiDi
-- ------------------------------------------------------------------------
-- Cambia la regla. Antes era quedar entre DiDi y Uber; ahora, por debajo de
-- DiDi, que era el mas barato de los dos.
--
-- Misma medicion de siempre: parada El Floron (Av. 10 de Agosto) ->
-- Universidad Central del Ecuador. 4,4 km, 7 minutos. DiDi cobra 1,50 y se
-- pidio 1,45.
--
--   Ride estandar     1,45   <- calibrado contra ese 1,45 exacto
--   DiDi              1,50
--   Ride hora pico    1,57
--   Ride nocturna     1,68
--   Uber              2,25
--
-- OJO: en hora pico y de noche se pasa de DiDi. No hay forma de conservar un
-- recargo por franja y quedar debajo a todas horas; se eligio conservarlo.
-- Para quedar debajo siempre habria que aplanar las franjas a 1,00.
--
-- Lo que gana el chofer en ese viaje baja a 1,23 (85 % de 1,45). Es el numero
-- mas bajo por el que ha pasado el proyecto: si dejan de conectarse, es esto.

update public.tarifas t
set tarifa_base      = v.base,
    costo_por_km     = v.km,
    costo_por_minuto = v.minuto,
    carrera_minima   = v.minima
from (values
  ('Tarifa Estandar',         0.35, 0.25, 0.07, 1.00),
  ('Tarifa Hora Pico Manana', 0.38, 0.27, 0.08, 1.08),
  ('Tarifa Hora Pico Tarde',  0.38, 0.27, 0.08, 1.08),
  ('Tarifa Nocturna',         0.40, 0.29, 0.08, 1.15)
) as v(nombre, base, km, minuto, minima)
where t.nombre = v.nombre;


-- Comprobacion
-- ------------------------------------------------------------------------
-- En franja estandar, el viaje medido debe dar 1,45 exactos.
--
--   select categoria, total
--   from public.cotizar_categorias(-0.1750, -78.4880, -0.2005, -78.5045, 4.4);
