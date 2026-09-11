-- Cierra la escritura directa en las tablas del viaje y rehace quien ve que perfil
-- ---------------------------------------------------------------------------
-- Segunda auditoria del 2026-09-11 (C1, C2, A1, M1 y M2). Deshacer con
-- `2026-09-11-cierra-escritura-directa-y-perfiles.deshacer.sql`.
--
-- C2. La logica del viaje vive en funciones (`solicitar_viaje`, `avanzar_viaje`,
-- `finalizar_viaje`, `cancelar_viaje`), pero la tabla seguia abierta por debajo:
-- `authenticated` tenia INSERT y UPDATE en todas las columnas de `viajes`, y las
-- politicas dejaban escribir al pasajero y al chofer de ese viaje. Con una
-- llamada directa a la API se podia bajar `tarifa_estimada` a un centavo antes
-- de cerrar, pasar a EN_CURSO sin codigo, cerrar sin cobro o cancelar sin multa.
-- Ni la app ni la web escriben en `viajes` ni en `ubicaciones`: todo va por las
-- funciones, que corren como dueno y no necesitan estos permisos.
--
-- C1 y A1. `can_view_role` dejaba a un chofer ver choferes y a un pasajero ver
-- pasajeros, pero no a la contraparte de su viaje. Dos efectos: cualquier
-- pasajero leia el correo y el telefono de todos los pasajeros, y
-- `viajes_detalle` —security_invoker, con `join` interno al perfil del
-- pasajero— devolvia 0 filas a un chofer de rol `driver`, que no veia el viaje
-- que acababa de aceptar. No se noto porque todos los viajes con chofer los
-- habia aceptado un superadmin, que ve todos los perfiles.
--
-- M1 y M2. El chat y el perfil admitian UPDATE en todas las columnas: cada parte
-- podia reescribir los mensajes de la otra, y cada usuario cambiarse `activo`
-- o su propia calificacion.

-- 1. Viajes y ubicaciones: solo las funciones escriben -----------------------

drop policy if exists viajes_pasajero_crea          on public.viajes;
drop policy if exists viajes_participante_actualiza on public.viajes;
revoke insert, update, delete, truncate on public.viajes from anon, authenticated;

drop policy if exists ubicaciones_del_viaje on public.ubicaciones;
create policy ubicaciones_del_viaje on public.ubicaciones
  for select to authenticated
  using (public.participa_en_viaje(viaje_id) or public.es_administrativo());
revoke insert, update, delete, truncate on public.ubicaciones from anon, authenticated;

-- Sin politica de escritura ya no se podian tocar, pero conservaban el permiso:
-- una politica nueva mal escrita las habria abierto sin mas.
revoke insert, update, delete, truncate
  on public.pagos, public.suscripciones_chofer, public.codigos_viaje
  from anon, authenticated;

-- 2. Perfiles: la contraparte del viaje si, el resto de su rol no ------------

create or replace function public.can_view_role(target_role public.user_role)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case public.current_user_role()
    when 'superadmin' then true
    when 'admin'      then target_role in ('passenger','driver','admin')
    else false
  end;
$$;

-- Definer para que la politica no dependa del RLS de `viajes` ni lo evalue fila
-- a fila: lee directo con los indices de pasajero y chofer.
create or replace function public.es_contraparte_de_viaje(p_perfil uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.viajes v
    where (v.pasajero_id = p_perfil and v.conductor_id = (select auth.uid()))
       or (v.conductor_id = p_perfil and v.pasajero_id = (select auth.uid()))
  );
$$;
revoke execute on function public.es_contraparte_de_viaje(uuid) from public, anon;
grant  execute on function public.es_contraparte_de_viaje(uuid) to authenticated;

drop policy if exists profiles_contraparte_del_viaje on public.profiles;
create policy profiles_contraparte_del_viaje on public.profiles
  for select to authenticated
  using (public.es_contraparte_de_viaje(id));

-- 5. Chat, perfil, pasajeros y avisos: solo lo que los clientes escriben -----

-- Los mensajes se escriben y se marcan con `enviar_mensaje` y
-- `marcar_mensajes_leidos` (security definer) desde las dos apps.
drop policy if exists mensajes_escritura    on public.mensajes;
drop policy if exists mensajes_marcar_leido on public.mensajes;
revoke insert, update, delete, truncate on public.mensajes from anon, authenticated;

-- Los clientes solo cambian estas cinco columnas de su perfil
-- (auth_service.dart y auth.ts). `activo`, `email` y `role` quedan fuera.
revoke update on public.profiles from anon, authenticated;
grant  update (full_name, phone, foto_url, must_change_password, updated_at)
  on public.profiles to authenticated;

-- `pasajeros` la crean `handle_new_user` y `solicitar_viaje`; la calificacion la
-- recalcula su disparador. Nadie escribe a mano.
drop policy if exists pasajeros_propio on public.pasajeros;
create policy pasajeros_propio on public.pasajeros
  for select to authenticated
  using (((select auth.uid()) = id) or public.es_administrativo());
revoke insert, update, delete, truncate on public.pasajeros from anon, authenticated;

-- Los avisos se marcan con `marcar_notificaciones_leidas`.
drop policy if exists notificaciones_marcar_leida on public.notificaciones;
revoke insert, update, delete, truncate on public.notificaciones from anon, authenticated;

-- `validar_calificacion` corria con los permisos de quien califica. Un chofer no
-- puede leer la fila de `pasajeros` de su pasajero, asi que el `select into`
-- salia vacio, las dos comparaciones daban NULL y el disparador dejaba pasar
-- cualquier cosa: el chofer podia calificar a quien quisiera con el id de uno
-- de sus viajes. Ahora lee como dueno, directo de `viajes`, y un viaje que no
-- encuentra es un error.
create or replace function public.validar_calificacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado public.enum_estado_viaje;
  v_pasajero uuid;
  v_conductor uuid;
begin
  select v.estado, v.pasajero_id, v.conductor_id
    into v_estado, v_pasajero, v_conductor
  from public.viajes v
  where v.id = new.viaje_id;

  if not found or v_estado is distinct from 'FINALIZADO' then
    raise exception 'Solo se califican viajes en estado FINALIZADO'
      using errcode = 'check_violation';
  end if;

  -- El evaluador y el evaluado deben ser las dos partes de ese viaje.
  if v_conductor is null or not (
       (new.calificador_id = v_pasajero  and new.calificado_id = v_conductor)
    or (new.calificador_id = v_conductor and new.calificado_id = v_pasajero)
  ) then
    raise exception 'La calificacion no corresponde a los participantes del viaje'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;
revoke execute on function public.validar_calificacion() from public, anon, authenticated;

-- Tres funciones definer que aun tenian `search_path=public` en vez de vacio.
alter function public.current_user_role()                 set search_path = '';
alter function public.current_user_must_change_password() set search_path = '';
alter function public.prevent_role_self_edit()            set search_path = '';
