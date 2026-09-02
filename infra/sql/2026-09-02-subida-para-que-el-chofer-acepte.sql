-- +0,30 al arranque y a la minima, para que el chofer acepte
-- ------------------------------------------------------------------------
-- Con el estandar en 1,45, un chofer de moto se llevaba 0,99 por el viaje de
-- referencia (4,4 km). Nadie acepta por eso, y una tarifa que nadie toma no es
-- barata: es inexistente.
--
-- Se sube 0,30 el arranque y la carrera minima de las cuatro franjas. La
-- calibracion es sobre la moto, que era la peor parada:
--
--   0,30 x 0,80 (factor moto) x 0,85 (parte del chofer) = 0,20 mas
--
-- Lo que gana el chofer en el viaje de 4,4 km:
--
--   Moto        0,99 -> 1,19
--   Estandar    1,23 -> 1,49
--   Confort     1,79 -> 2,16
--   XL          2,22 -> 2,68
--
-- OJO: esto rompe el "por debajo de DiDi" del cambio anterior. El estandar
-- pasa de 1,45 a 1,75 y DiDi cobra 1,50. Ride queda entre DiDi y Uber (2,25),
-- mas cerca del primero. Es el intercambio que se acepto.

update public.tarifas
set tarifa_base    = tarifa_base + 0.30,
    carrera_minima = carrera_minima + 0.30
where nombre in ('Tarifa Estandar', 'Tarifa Hora Pico Manana',
                 'Tarifa Hora Pico Tarde', 'Tarifa Nocturna');


-- Comprobacion
-- ------------------------------------------------------------------------
-- El chofer de moto debe llevarse 1,19 en el viaje de referencia.
--
--   select categoria, total, gana_conductor
--   from public.cotizar_categorias(-0.1750, -78.4880, -0.2005, -78.5045, 4.4);
