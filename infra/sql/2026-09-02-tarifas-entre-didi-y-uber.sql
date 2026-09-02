-- Tarifas posicionadas entre DiDi y Uber
-- ------------------------------------------------------------------------
-- Sustituye a 2026-09-02-tarifas-referenciales.sql, del mismo día. Aquel
-- derivaba los precios del taxi de Quito menos 10 %; este los fija contra la
-- competencia real, que es lo que ve el pasajero al comparar.
--
-- Medición: parada El Florón (Av. 10 de Agosto) → Universidad Central del
-- Ecuador. 4,4 km, 7 minutos.
--
--   DiDi              1,50
--   Ride estándar     1,86   <- casi el punto medio exacto (1,88)
--   Ride hora pico    2,03
--   Ride nocturna     2,15
--   Uber              2,25
--
-- La regla —ni tan barato como DiDi ni tan caro como Uber— se aplica a las
-- tres franjas, no solo a la estándar. Por eso el recargo por franja baja de
-- +30 %/+15 % a +15 %/+8 %: a +30 %, la nocturna se pasaba de Uber.
--
-- `costo_por_minuto` se escribe por coherencia con la documentación, pero no
-- se cobra: cotizar_viaje calcula (tarifa_base + costo_por_km * km) * factor.
--
-- Los factores de `categorias_vehiculo` no se tocan: moto 0,65, estándar 1,00,
-- confort 1,30 y XL 1,55. Confort y XL quedan por encima de los 2,25 de Uber
-- a propósito: se comparó contra su categoría de coche normal.

update public.tarifas t
set tarifa_base      = v.base,
    costo_por_km     = v.km,
    costo_por_minuto = v.minuto,
    carrera_minima   = v.minima
from (values
  ('Tarifa Estandar',  0.45, 0.32, 0.09, 1.30),
  ('Tarifa Hora Pico', 0.49, 0.35, 0.10, 1.40),
  ('Tarifa Nocturna',  0.52, 0.37, 0.10, 1.50)
) as v(nombre, base, km, minuto, minima)
where t.nombre = v.nombre;


-- Comprobación
-- ------------------------------------------------------------------------
-- El trayecto medido, con los cuatro tipos de vehículo. En hora pico el
-- estándar debe dar 2,03; fuera de franja, 1,86.
--
--   select categoria, total
--   from public.cotizar_categorias(-0.1750, -78.4880, -0.2005, -78.5045, 4.4);
