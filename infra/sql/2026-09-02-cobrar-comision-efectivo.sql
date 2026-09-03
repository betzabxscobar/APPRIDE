-- Cobrar la comision en los viajes en efectivo
-- ------------------------------------------------------------------------
-- Al cerrar un viaje en efectivo, el chofer se queda el importe entero: queda
-- debiendole a la app su comision. Con tarjeta es al reves, pero ese
-- movimiento NO se crea aqui: se creara cuando la pasarela confirme el cobro.
-- Apuntar dinero que nadie ha cobrado es justo el error a evitar.
--
-- Y un chofer que debe mas del limite no puede ponerse en linea. Sin eso,
-- deber sale gratis y la comision vuelve a ser un numero en pantalla.

create or replace function public.finalizar_viaje(p_viaje_id uuid)
 returns numeric language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_estimada numeric;
  v_metodo uuid;
  v_tipo text;
  v_pasajero uuid;
  v_tarifa uuid;
  v_pct numeric;
  v_comision numeric;
begin
  select tarifa_estimada, pasajero_id, tarifa_id
    into v_estimada, v_pasajero, v_tarifa
  from public.viajes
  where id = p_viaje_id and conductor_id = v_uid and estado = 'EN_CURSO';

  if v_estimada is null then
    raise exception 'Solo el conductor puede cerrar un viaje en curso'
      using errcode = '42501';
  end if;

  update public.viajes
  set estado = 'FINALIZADO', fecha_fin = now(), tarifa_final = v_estimada
  where id = p_viaje_id;

  select id, tipo into v_metodo, v_tipo
  from public.metodos_pago
  where pasajero_id = v_pasajero and predeterminado limit 1;

  insert into public.pagos (viaje_id, metodo_pago_id, monto, tipo, estado)
  values (p_viaje_id, v_metodo, v_estimada, 'pago',
          case when v_tipo = 'efectivo' then 'completado' else 'pendiente' end);

  if v_tipo = 'efectivo' then
    -- El porcentaje de LA TARIFA DEL VIAJE, no el de hoy: lo ya cobrado no se
    -- recalcula si mañana cambia el reparto.
    select porcentaje_conductor into v_pct from public.tarifas where id = v_tarifa;
    v_comision := v_estimada - round(v_estimada * coalesce(v_pct, 0.85), 2);

    if v_comision > 0 then
      insert into public.movimientos_chofer
        (conductor_id, viaje_id, tipo, monto, concepto)
      values (v_uid, p_viaje_id, 'comision', -v_comision,
              'Comision del viaje cobrado en efectivo')
      on conflict do nothing;
    end if;
  end if;

  return v_estimada;
end;
$function$;

create or replace function public.validar_disponibilidad_conductor_real()
 returns trigger language plpgsql set search_path to ''
as $function$
declare
  v_saldo numeric;
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
  end if;

  return new;
end;
$function$;


-- Comprobacion
-- ------------------------------------------------------------------------
-- Tras cerrar un viaje en efectivo de 1,75 con reparto 0,85, el chofer debe
-- tener un movimiento de -0,26 y su saldo debe bajar en esa cantidad.
--
--   select tipo, monto, concepto from public.movimientos_chofer
--   order by created_at desc limit 5;
