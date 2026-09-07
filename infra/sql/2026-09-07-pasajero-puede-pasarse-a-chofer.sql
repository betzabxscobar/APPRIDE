-- Un pasajero puede pasarse a chofer
-- ---------------------------------------------------------------------------
-- El rol se decidía al registrarse y no había vuelta atrás. Quien entró como
-- pasajero y luego quiso conducir tenía que abrir otra cuenta, y encima
-- chocaba con el índice único del teléfono, que solo admite un número por
-- cuenta: acababa inventándose un celular.
--
-- Había además un callejón sin salida en la app: `switchView` deja a un
-- pasajero abrir la vista de chofer «solo si ya registró un vehículo», pero
-- registrar un vehículo exige tener ficha de conductor. Nunca se podía.
--
-- El cambio NO reparte privilegios. Entra en `conductores` con
-- estado_aprobacion 'pendiente', y `solo_administracion_aprueba` le impide
-- aprobarse solo: sin la revisión de administración no puede ponerse
-- disponible ni ver solicitudes. Lo único que cambia de inmediato es qué
-- pantalla ve y que ya puede subir sus papeles.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. La única excepción al candado del rol
-- ---------------------------------------------------------------------------
-- `prevent_role_self_edit` impedía cualquier cambio de rol sobre uno mismo.
-- Se abre una sola puerta, y bien estrecha: pasajero -> chofer. Todo lo demás
-- —y sobre todo subirse a administrativo— sigue prohibido.
create or replace function public.prevent_role_self_edit()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if auth.uid() = old.id and new.role is distinct from old.role then
    if not (old.role = 'passenger' and new.role = 'driver') then
      raise exception 'cannot change own role';
    end if;
  end if;

  return new;
end;
$function$;


-- 2. El cambio
-- ---------------------------------------------------------------------------
create or replace function public.quiero_ser_chofer()
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_rol public.user_role;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  select role into v_rol from public.profiles where id = v_uid;

  if v_rol is null then
    raise exception 'No encontramos tu perfil' using errcode = 'no_data_found';
  end if;

  -- Pedirlo dos veces no es un error: ya esta hecho.
  if v_rol = 'driver' then
    return;
  end if;

  if v_rol <> 'passenger' then
    raise exception 'Solo una cuenta de pasajero puede pasarse a chofer'
      using errcode = '42501';
  end if;

  -- Con un viaje pedido o en marcha, cambiar de rol le cambia la pantalla
  -- debajo de los pies y deja el viaje huerfano.
  if exists (
    select 1 from public.viajes
    where pasajero_id = v_uid
      and estado not in ('FINALIZADO', 'CANCELADO', 'SIN_CONDUCTOR')
  ) then
    raise exception 'Termina tu viaje antes de pasarte a chofer'
      using errcode = 'check_violation';
  end if;

  update public.profiles set role = 'driver' where id = v_uid;

  -- Su ficha de chofer nace pendiente de revision, como la de cualquiera.
  insert into public.conductores (id) values (v_uid) on conflict do nothing;

  -- La fila de `pasajeros` se queda: su historial de viajes cuelga de ella.
end;
$function$;


-- 3. Permisos
-- ---------------------------------------------------------------------------
revoke execute on function public.quiero_ser_chofer() from public, anon;
grant execute on function public.quiero_ser_chofer() to authenticated;
