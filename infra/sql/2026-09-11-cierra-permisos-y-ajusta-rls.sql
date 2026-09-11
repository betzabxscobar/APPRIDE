-- Cierra permisos y ajusta RLS antes de produccion
-- ---------------------------------------------------------------------------
-- Sale de la auditoria del 2026-09-11. Cada bloque dice que hallazgo cierra.
-- Se revoca en vez de borrar: todo se deshace con un `grant`.

-- A1. Localizar choferes. Las dos son `definer`, no miran quien llama y el
-- radio no tiene tope: devolvian nombre y distancia (a 10 m) de cada chofer en
-- linea a cualquier usuario registrado, y con tres consultas se triangulaba
-- donde estaba. Ningun cliente las usa: el emparejamiento es
-- `solicitudes_abiertas()`.
revoke execute on function public.conductores_cercanos(double precision, double precision, double precision)
  from public, anon, authenticated;
revoke execute on function public.conductores_en_celdas(text[])
  from public, anon, authenticated;

-- B3. Sin nadie que las llame. `suscripcion_vigente` si se usa, pero solo
-- desde funciones `definer` (aceptar_viaje, mi_suscripcion,
-- solicitudes_abiertas y el disparador de la cuota), que corren como su dueno:
-- cerrarla no les afecta, y deja de contestar a cualquiera si un chofer
-- concreto tiene la cuota al dia.
revoke execute on function public.saldo_chofer(uuid) from public, anon, authenticated;
revoke execute on function public.current_user_must_change_password() from public, anon, authenticated;
revoke execute on function public.confirmar_pago_efectivo(uuid) from public, anon, authenticated;
revoke execute on function public.suscripcion_vigente(uuid) from public, anon, authenticated;

-- B2. Sin sesion no hay nada que cotizar. La migracion 19 ya las habia cerrado;
-- al recrearlas con otra firma volvieron a heredar el permiso por defecto. Se
-- concede a `authenticated` a proposito: `cotizar_categorias` es `invoker` y
-- llama a `cotizar_viaje` con los permisos de quien pregunta.
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = any (array['cotizar_viaje', 'cotizar_categorias', 'es_superadmin',
                                 'posicion_vigente_minutos', 'radio_busqueda_km', 'radio_llegada_km',
                                 'desvio_maximo_factor', 'duracion_minima_viaje_seg'])
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;

-- Funciones de disparador: por RPC no hacen nada, pero el linter las marca.
-- Postgres no comprueba EXECUTE al disparar, asi que siguen funcionando.
revoke execute on function public.solo_administracion_aprueba() from public, anon, authenticated;
revoke execute on function public.solo_administracion_revisa_documentos() from public, anon, authenticated;
revoke execute on function public.generar_codigo_viaje() from public, anon, authenticated;

-- Para que no vuelva a pasar: las funciones nuevas ya no nacen ejecutables sin
-- sesion. `authenticated` y `service_role` las siguen recibiendo por el permiso
-- por defecto de Supabase en el esquema public.
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from anon;

-- B8. `auth.uid()` dentro de `(select ...)` se evalua una vez por consulta, no
-- una por fila. Misma logica que antes.
alter policy profiles_select_own on public.profiles
  using ((select auth.uid()) = id);
alter policy profiles_select_by_role on public.profiles
  using (((select auth.uid()) = id) or public.can_view_role(role));
alter policy profiles_update_own on public.profiles
  using ((select auth.uid()) = id)
  with check (((select auth.uid()) = id)
              and (role = (select p.role from public.profiles p where p.id = (select auth.uid()))));

create index if not exists viajes_vehiculo_conductor_idx
  on public.viajes (vehiculo_id, conductor_id);

-- A2. Avisos de PayPal ya procesados. PayPal entrega cada aviso «al menos una
-- vez» y reintenta los que no confirma a tiempo: sin esto, un reintento sumaba
-- otro mes de cuota. Solo la escribe `webhook-paypal`, con la service_role.
create table if not exists public.eventos_paypal (
  id          text primary key,
  tipo        text,
  recibido_en timestamptz not null default now()
);
alter table public.eventos_paypal enable row level security;
revoke all on public.eventos_paypal from anon, authenticated;
comment on table public.eventos_paypal is
  'Ids de eventos de PayPal ya procesados por webhook-paypal. Sin politicas: solo service_role.';
