-- Deshace `2026-09-11-cierra-escritura-directa-y-perfiles.sql`
-- ---------------------------------------------------------------------------
-- Solo si esa migracion rompe algo en produccion y hace falta volver YA. Deja
-- la base exactamente como estaba el 2026-09-11 antes del cambio, con los
-- agujeros C1, C2, A1, M1 y M2 abiertos otra vez: arreglar y volver a aplicar.
-- Las definiciones se copiaron de pg_policies y pg_get_functiondef antes de
-- aplicar.

grant insert, update, delete, truncate on public.viajes      to authenticated;
grant insert, update, delete, truncate on public.ubicaciones to authenticated;
grant insert, update, delete, truncate
  on public.pagos, public.suscripciones_chofer, public.codigos_viaje,
     public.mensajes, public.pasajeros, public.notificaciones
  to authenticated;
grant update on public.profiles to authenticated;

create policy viajes_pasajero_crea on public.viajes
  for insert to authenticated
  with check ((select auth.uid()) = pasajero_id);
create policy viajes_participante_actualiza on public.viajes
  for update to authenticated
  using ((((select auth.uid()) = pasajero_id) or ((select auth.uid()) = conductor_id)) or public.es_administrativo())
  with check ((((select auth.uid()) = pasajero_id) or ((select auth.uid()) = conductor_id)) or public.es_administrativo());

drop policy if exists ubicaciones_del_viaje on public.ubicaciones;
create policy ubicaciones_del_viaje on public.ubicaciones
  for all to authenticated
  using (public.participa_en_viaje(viaje_id) or public.es_administrativo())
  with check (public.participa_en_viaje(viaje_id));

create or replace function public.can_view_role(target_role public.user_role)
returns boolean language sql stable set search_path = '' as $$
  select case public.current_user_role()
    when 'superadmin' then true
    when 'admin'      then target_role in ('passenger','driver','admin')
    when 'driver'     then target_role = 'driver'
    when 'passenger'  then target_role = 'passenger'
    else false
  end;
$$;

drop policy if exists profiles_contraparte_del_viaje on public.profiles;
drop function if exists public.es_contraparte_de_viaje(uuid);

create policy mensajes_escritura on public.mensajes
  for insert to authenticated
  with check ((autor_id = (select auth.uid())) and public.participa_en_viaje(viaje_id) and (exists (
    select 1 from public.viajes v
    where v.id = mensajes.viaje_id and v.conductor_id is not null
      and ((v.estado <> all (array['FINALIZADO','CANCELADO','SIN_CONDUCTOR']::public.enum_estado_viaje[]))
           or (v.fecha_fin > (now() - interval '24 hours'))))));
create policy mensajes_marcar_leido on public.mensajes
  for update to authenticated
  using (public.participa_en_viaje(viaje_id) and (autor_id <> (select auth.uid())))
  with check (public.participa_en_viaje(viaje_id) and (autor_id <> (select auth.uid())));

drop policy if exists pasajeros_propio on public.pasajeros;
create policy pasajeros_propio on public.pasajeros
  for all to authenticated
  using (((select auth.uid()) = id) or public.es_administrativo())
  with check ((select auth.uid()) = id);

create policy notificaciones_marcar_leida on public.notificaciones
  for update to authenticated
  using ((select auth.uid()) = usuario_id)
  with check ((select auth.uid()) = usuario_id);

create or replace function public.validar_calificacion()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_viaje record;
begin
  select v.estado, p.id as pasajero_uid, c.id as conductor_uid
    into v_viaje
  from public.viajes v
  join public.pasajeros p on p.id = v.pasajero_id
  left join public.conductores c on c.id = v.conductor_id
  where v.id = new.viaje_id;

  if v_viaje.estado <> 'FINALIZADO' then
    raise exception 'Solo se califican viajes en estado FINALIZADO'
      using errcode = 'check_violation';
  end if;

  if not (
       (new.calificador_id = v_viaje.pasajero_uid  and new.calificado_id = v_viaje.conductor_uid)
    or (new.calificador_id = v_viaje.conductor_uid and new.calificado_id = v_viaje.pasajero_uid)
  ) then
    raise exception 'La calificacion no corresponde a los participantes del viaje'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

alter function public.current_user_role()                 set search_path = public;
alter function public.current_user_must_change_password() set search_path = public;
alter function public.prevent_role_self_edit()            set search_path = public;
