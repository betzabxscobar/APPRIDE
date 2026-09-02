-- Deja `pagos` listo para una pasarela, sea cual sea
-- ------------------------------------------------------------------------
-- Trabajo independiente del proveedor: sirve igual con Deuna, con PayPhone o
-- con la que acabe eligiendose. Se hace antes de integrar nada porque sin esto
-- no se puede conciliar ni protegerse de un webhook repetido.
--
-- 1. `pagos` no guardaba de que cobro externo viene cada fila. Sin la
--    referencia de la pasarela no hay forma de responder «este cobro, de que
--    viaje es» ni de detectar que un webhook ya se proceso.
--
-- 2. `finalizar_viaje` marcaba el pago como 'completado' en cuanto el chofer
--    cerraba el viaje, solo con que el pasajero tuviera metodo predeterminado.
--    Con efectivo es una aproximacion razonable: el chofer recibe el dinero en
--    la mano. Con tarjeta seria dar por cobrado algo que nadie ha cobrado, y
--    ese es justo el error que deja un agujero de dinero.

alter table public.pagos
  add column if not exists proveedor          text,
  add column if not exists referencia_externa text,
  add column if not exists datos              jsonb,
  add column if not exists actualizado_en     timestamptz not null default now();

comment on column public.pagos.proveedor is
  'Quien cobro: deuna, payphone... NULL en efectivo, que no pasa por nadie.';
comment on column public.pagos.referencia_externa is
  'Id de la transaccion en la pasarela. Es la clave para conciliar y para no '
  'cobrar dos veces.';
comment on column public.pagos.datos is
  'Respuesta cruda de la pasarela. Se guarda entera porque el dia que un cobro '
  'se discuta, el resumen no sirve.';

-- La misma transaccion no puede entrar dos veces. Esto es lo que hace que un
-- webhook reintentado sea inofensivo, y los webhooks se reintentan.
create unique index if not exists pagos_referencia_externa_unica
  on public.pagos (proveedor, referencia_externa)
  where referencia_externa is not null;

create index if not exists pagos_viaje_idx on public.pagos (viaje_id);

-- El estado del cobro depende del metodo, no de que exista un metodo.
create or replace function public.finalizar_viaje(p_viaje_id uuid)
 returns numeric
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_estimada numeric;
  v_metodo uuid;
  v_tipo text;
  v_pasajero uuid;
begin
  select tarifa_estimada, pasajero_id into v_estimada, v_pasajero
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
  where pasajero_id = v_pasajero and predeterminado
  limit 1;

  insert into public.pagos (viaje_id, metodo_pago_id, monto, tipo, estado)
  values (p_viaje_id, v_metodo, v_estimada, 'pago',
          case when v_tipo = 'efectivo' then 'completado'
               else 'pendiente' end);

  return v_estimada;
end;
$function$;
