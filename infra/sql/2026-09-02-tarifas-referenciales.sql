-- Vuelve a las tarifas referenciales de Quito menos 10 %
-- ------------------------------------------------------------------------
-- Deshace la bajada del 2026-09-01 («Baja los precios por debajo de inDrive»,
-- d784544) y devuelve los valores que documenta la primera tabla de
-- docs/TARIFAS.md. Se pidió así.
--
-- Lo que hay que saber antes de volver a tocar esto:
--
-- 1. `costo_por_minuto` se guarda pero NO se cobra. `cotizar_viaje` calcula
--    (tarifa_base + costo_por_km * km) * factor, y el minuto no aparece. Se
--    escribe igual para que la columna no contradiga a la documentación.
--
-- 2. Sobre el único trayecto que se midió de verdad en Quito —8,4 km hasta la
--    Universidad Central, donde inDrive recomendaba 3,10— estos valores dejan
--    a Ride en 3,78 de día y 4,85 de noche. Por encima. Es lo que la bajada
--    del 2026-09-01 intentaba corregir.
--
-- 3. Los factores de `categorias_vehiculo` no se tocan: moto 0,65,
--    estándar 1,00, confort 1,30 y XL 1,55, sobre el precio y sobre la mínima.

update public.tarifas t
set tarifa_base      = v.base,
    costo_por_km     = v.km,
    costo_por_minuto = v.minuto,
    carrera_minima   = v.minima
from (values
  ('Tarifa Estandar',  0.50, 0.39, 0.10, 1.44),
  ('Tarifa Nocturna',  0.65, 0.50, 0.13, 1.87),
  ('Tarifa Hora Pico', 0.58, 0.45, 0.12, 1.65)
) as v(nombre, base, km, minuto, minima)
where t.nombre = v.nombre;


-- Comprobación
-- ------------------------------------------------------------------------
-- Un viaje de 8,4 km en franja estándar debe dar 4,36 en hora pico y 3,78 en
-- estándar, y cada tipo de vehículo ese número por su factor:
--
--   select categoria, total
--   from public.cotizar_categorias(-0.1807, -78.4678, -0.2299, -78.5249, 8.4);
