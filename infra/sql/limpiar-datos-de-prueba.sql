-- Limpieza de los datos de prueba antes de abrir al publico
-- ---------------------------------------------------------------------------
-- NO se aplica solo, y no lo aplica ninguna herramienta: es un borrado
-- permanente en la base de produccion. Revisalo, haz una copia (pg_dump, o
-- Database -> Backups si el plan lo tiene) y ejecutalo en el SQL Editor.
--
-- Termina en ROLLBACK a proposito: la primera vez solo ensena cuanto borraria.
-- Cuando los numeros cuadren, cambia la ultima linea por COMMIT y ejecutalo
-- otra vez.
--
-- Estado al 2026-09-11: 17 viajes (15 cancelados y 2 finalizados), 2 pagos en
-- `pendiente` desde hace dias, 55 notificaciones, 1 ticket y los movimientos de
-- billetera de esos viajes. Todo son pruebas del equipo.
--
-- NO toca cuentas, perfiles, choferes, vehiculos, documentos, cuentas
-- bancarias, zonas, tarifas ni las cuotas de cortesia.

begin;

select 'antes' as momento,
       (select count(*) from public.viajes)             as viajes,
       (select count(*) from public.pagos)              as pagos,
       (select count(*) from public.movimientos_chofer) as movimientos,
       (select count(*) from public.notificaciones)     as notificaciones,
       (select count(*) from public.tickets_soporte)    as tickets,
       (select count(*) from public.suscripciones_chofer
         where proveedor = 'paypal' and estado = 'pendiente') as cuotas_sandbox,
       (select count(*) from public.conductores where disponible) as en_linea;

-- `pagos` y `movimientos_chofer` apuntan a `viajes` con ON DELETE RESTRICT:
-- van primero, o el borrado de viajes falla.
delete from public.movimientos_chofer;
delete from public.pagos;

-- `ubicaciones`, `calificaciones`, `mensajes` y `codigos_viaje` caen en
-- cascada; el promedio de cada chofer se recalcula con su disparador.
delete from public.viajes;
delete from public.tickets_soporte;
delete from public.notificaciones;

-- Suscripciones abiertas contra sandbox: en produccion no existen. Las de
-- cortesia no se tocan.
delete from public.suscripciones_chofer where proveedor = 'paypal' and estado = 'pendiente';

-- Que nadie arranque «en linea» con una posicion de las pruebas.
update public.conductores set disponible = false where disponible;

select 'despues' as momento,
       (select count(*) from public.viajes)             as viajes,
       (select count(*) from public.pagos)              as pagos,
       (select count(*) from public.movimientos_chofer) as movimientos,
       (select count(*) from public.notificaciones)     as notificaciones,
       (select count(*) from public.tickets_soporte)    as tickets,
       (select count(*) from public.suscripciones_chofer
         where proveedor = 'paypal' and estado = 'pendiente') as cuotas_sandbox,
       (select count(*) from public.conductores where disponible) as en_linea;

rollback;  -- cambiar por COMMIT cuando los numeros cuadren
