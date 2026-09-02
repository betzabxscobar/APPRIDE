-- Multiplicadores por vehiculo y carrera minima
-- ------------------------------------------------------------------------
-- Los factores estaban calibrados para unos precios tres veces mayores. Al
-- bajar la tarifa se quedaron sin nada que multiplicar y el chofer dejo de
-- ganar: en un viaje de 2 km, un chofer de moto se llevaba 55 centavos.
--
-- El agujero no eran solo los factores. La carrera minima TAMBIEN se multiplica
-- por el factor, asi que con la minima en 1,00 el suelo de la moto era 0,65.
-- Bajar la tarifa sin mirar la minima deja sin suelo los viajes cortos, que es
-- justo donde el chofer ya gana menos.
--
-- Nada de esto toca el viaje de referencia: 4,4 km en estandar sigue costando
-- 1,45, porque 1,45 esta por encima de la minima.
--
-- Lo que gana el chofer, antes y despues:
--
--                   4,4 km            2 km
--   Moto        0,80 -> 0,99     0,55 -> 0,82
--   Estandar    1,23 -> 1,23     0,85 -> 1,02
--   Confort     1,60 -> 1,79     1,11 -> 1,48
--   XL          1,91 -> 2,22     1,32 -> 1,84

-- 1. Los factores.
update public.categorias_vehiculo c
set factor = v.factor
from (values ('moto', 0.80), ('estandar', 1.00), ('confort', 1.45), ('xl', 1.80))
     as v(id, factor)
where c.id = v.id;

-- 2. La carrera minima, en las cuatro franjas.
update public.tarifas t
set carrera_minima = v.minima
from (values
  ('Tarifa Estandar',         1.20),
  ('Tarifa Hora Pico Manana', 1.30),
  ('Tarifa Hora Pico Tarde',  1.30),
  ('Tarifa Nocturna',         1.38)
) as v(nombre, minima)
where t.nombre = v.nombre;


-- Comprobacion
-- ------------------------------------------------------------------------
-- El viaje de referencia no se mueve: estandar sigue en 1,45.
--
--   select categoria, total, gana_conductor
--   from public.cotizar_categorias(-0.1750, -78.4880, -0.2005, -78.5045, 4.4);
