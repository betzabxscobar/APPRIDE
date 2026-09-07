-- Los teléfonos a los que mandar el aviso (primer paso del push)
-- ---------------------------------------------------------------------------
-- Hoy las notificaciones existen dentro de la app —la tabla `notificaciones` y
-- la campana— pero no salen al teléfono: con Ride cerrada, nadie se entera de
-- nada. Para que lleguen como las de WhatsApp hace falta un servicio de push,
-- y Supabase no tiene ninguno.
--
-- Esto es la parte que NO depende del proveedor: dónde se guarda el token.
--
-- Un push no se manda «al usuario»: se manda a un token que el sistema
-- operativo le da a esa instalación concreta. La misma persona puede tener el
-- teléfono y la tablet, y el token se renueva solo cada cierto tiempo, así que
-- la tabla guarda varios por persona.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.

create table if not exists public.dispositivos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  plataforma text not null check (plataforma in ('android', 'ios', 'web')),
  creado_en timestamptz not null default now(),
  visto_en timestamptz not null default now(),
  -- Un token identifica una instalación, no una persona. Si reaparece con otro
  -- usuario es que alguien más entró en ese mismo teléfono: la fila se muda,
  -- no se duplica, o los avisos seguirían yendo a quien ya salió.
  unique (token)
);

create index if not exists dispositivos_usuario_idx
  on public.dispositivos (usuario_id);

alter table public.dispositivos enable row level security;

drop policy if exists dispositivos_propios on public.dispositivos;
create policy dispositivos_propios on public.dispositivos
  for all to authenticated
  using (usuario_id = (select auth.uid()) or public.es_administrativo())
  with check (usuario_id = (select auth.uid()));


-- Alta o refresco del token de este teléfono.
create or replace function public.registrar_dispositivo(
  p_token text,
  p_plataforma text
)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_token text := nullif(trim(coalesce(p_token, '')), '');
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;
  if v_token is null then
    raise exception 'Falta el token del dispositivo' using errcode = 'check_violation';
  end if;
  if p_plataforma not in ('android', 'ios', 'web') then
    raise exception 'Plataforma no valida' using errcode = 'check_violation';
  end if;

  insert into public.dispositivos (usuario_id, token, plataforma)
  values (v_uid, v_token, p_plataforma)
  on conflict (token) do update
    set usuario_id = excluded.usuario_id,
        plataforma = excluded.plataforma,
        visto_en = now();
end;
$function$;


-- Al cerrar sesión, este teléfono deja de recibir los avisos de esa cuenta.
create or replace function public.olvidar_dispositivo(p_token text)
 returns void
 language sql
 security definer
 set search_path to ''
as $function$
  delete from public.dispositivos
  where token = p_token and usuario_id = (select auth.uid());
$function$;


-- Permisos
-- ---------------------------------------------------------------------------
revoke execute on function public.registrar_dispositivo(text, text) from public, anon;
revoke execute on function public.olvidar_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text) to authenticated;
grant execute on function public.olvidar_dispositivo(text) to authenticated;
grant select, insert, update, delete on public.dispositivos to authenticated;


-- LO QUE FALTA PARA QUE EL PUSH LLEGUE DE VERDAD
-- ---------------------------------------------------------------------------
-- 1. Un proyecto de Firebase con el identificador DEFINITIVO de la app. Hoy es
--    `com.example.ride`, el de la plantilla de Flutter: Google Play no lo
--    acepta y Firebase ata su configuración a ese nombre, así que cambiarlo
--    después obliga a rehacer el proyecto entero.
-- 2. El `google-services.json` de ese proyecto dentro de `android/app/`. Sin
--    ese archivo, añadir los paquetes de Firebase **rompe la compilación**:
--    por eso todavía no están en `pubspec.yaml`.
-- 3. La credencial de servicio de Firebase guardada como secreto en Supabase,
--    y una Edge Function que la use para enviar cuando entre una fila en
--    `notificaciones`.
-- 4. Para iOS, además, una cuenta de Apple Developer de pago: sin ella no hay
--    certificado de push y el iPhone no recibe nada.
