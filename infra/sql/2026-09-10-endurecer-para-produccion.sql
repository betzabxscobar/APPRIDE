-- Ajustes de la auditoria previa al despliegue
-- ---------------------------------------------------------------------------
-- Nada de esto cambia lo que la app hace. Son tres cosas que no molestan con
-- 16 viajes y una base de pruebas, y que si molestan el dia que haya trafico
-- de verdad.
--
-- Se aplica con:
--   supabase db push
-- o pegandolo entero en el editor SQL del proyecto.

-- ---------------------------------------------------------------------------
-- 1. Las claves foraneas que no tenian indice
-- ---------------------------------------------------------------------------
-- Postgres no indexa el lado que apunta de una clave foranea. Sin indice, cada
-- borrado del lado apuntado recorre la tabla entera para comprobar que nadie lo
-- referencia; y los `join` por esa columna van a peor.

create index if not exists calificaciones_calificador_idx on public.calificaciones (calificador_id);
create index if not exists cuentas_bancarias_chofer_banco_idx on public.cuentas_bancarias_chofer (banco);
create index if not exists documentos_conductor_revisado_por_idx on public.documentos_conductor (revisado_por);
create index if not exists mensajes_autor_idx on public.mensajes (autor_id);
create index if not exists movimientos_chofer_registrado_por_idx on public.movimientos_chofer (registrado_por);
create index if not exists tickets_soporte_respondido_por_idx on public.tickets_soporte (respondido_por);
create index if not exists tickets_soporte_viaje_idx on public.tickets_soporte (viaje_id);
create index if not exists viajes_cancelado_por_idx on public.viajes (cancelado_por);
create index if not exists viajes_tarifa_idx on public.viajes (tarifa_id);
create index if not exists viajes_vehiculo_idx on public.viajes (vehiculo_id);
create index if not exists zonas_conductor_zona_idx on public.zonas_conductor (zona_id);

-- ---------------------------------------------------------------------------
-- 2. `auth.uid()` en las politicas, una vez por consulta y no por fila
-- ---------------------------------------------------------------------------
-- Escrito suelto dentro de una politica, Postgres lo reevalua PARA CADA FILA
-- que examina. Envuelto en un `select` lo trata como constante y lo calcula una
-- sola vez. Mismo resultado, mismo permiso.

drop policy if exists suscripciones_chofer_lee_el_suyo on public.suscripciones_chofer;
create policy suscripciones_chofer_lee_el_suyo
  on public.suscripciones_chofer
  for select
  to authenticated
  using (conductor_id = (select auth.uid()) or public.es_superadmin());

-- ---------------------------------------------------------------------------
-- 3. `anon` no escribe en ninguna tabla
-- ---------------------------------------------------------------------------
-- Supabase da por defecto INSERT, UPDATE y DELETE a `anon` sobre todo el schema
-- `public`, y aqui eso eran 25 tablas. El RLS lo tapaba —comprobado contra la
-- API real: sin sesion no se lee ni se escribe nada, ni siquiera un `update`
-- que solo cambie `disponible`—, pero es una red de seguridad de mas. El dia
-- que alguien anada una tabla y se olvide del RLS, o escriba una politica de
-- mas, esa tabla queda abierta a internet sin autenticar.
--
-- Nadie sin sesion tiene por que escribir en Ride. El registro no se ve
-- afectado: el perfil lo crea el trigger `handle_new_user`, que es
-- `security definer`, y para cuando el cliente toca una tabla ya es
-- `authenticated`.

do $$
declare t record;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('revoke insert, update, delete on public.%I from anon', t.tablename);
  end loop;
end $$;
