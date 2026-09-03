-- La billetera del chofer, como en Uber, DiDi o inDrive
-- ------------------------------------------------------------------------
-- Hasta ahora la comision del 15 % era un numero en pantalla: se calculaba, se
-- enseñaba en `ganancias_conductor` y no la cobraba nadie. En un viaje en
-- efectivo el chofer se quedaba el importe entero y la app no recibia nada.
--
-- Un solo saldo por chofer, con signo:
--   negativo -> el chofer le debe a la app   (viajes cobrados en efectivo)
--   positivo -> la app le debe al chofer     (viajes cobrados con tarjeta)
--
-- Esto no depende de ninguna pasarela: funciona hoy, solo con efectivo, y es
-- de hecho como cobran Uber y DiDi en Ecuador, donde el efectivo manda.

create table if not exists public.movimientos_chofer (
  id             uuid primary key default gen_random_uuid(),
  conductor_id   uuid not null references public.conductores(id) on delete restrict,
  viaje_id       uuid references public.viajes(id) on delete restrict,
  tipo           text not null check (tipo in ('comision','abono_viaje','liquidacion','ajuste')),
  -- Un solo signo para todo, en vez de dos columnas «debe» y «haber»: la
  -- confusion clasica de un libro de cuentas es cual de las dos suma.
  monto          numeric(10,2) not null check (monto <> 0),
  concepto       text,
  registrado_por uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);

-- Un viaje no genera dos veces el mismo movimiento. Es lo que hace que
-- reintentar un cierre —o un webhook— no duplique dinero.
create unique index if not exists movimientos_chofer_viaje_tipo_unico
  on public.movimientos_chofer (viaje_id, tipo) where viaje_id is not null;

create index if not exists movimientos_chofer_idx
  on public.movimientos_chofer (conductor_id, created_at desc);

alter table public.movimientos_chofer enable row level security;

create policy movimientos_chofer_lee_los_suyos
  on public.movimientos_chofer for select to authenticated
  using (conductor_id = (select auth.uid()) or public.es_administrativo());

create policy movimientos_chofer_escribe_administracion
  on public.movimientos_chofer for all to authenticated
  using (public.es_administrativo()) with check (public.es_administrativo());

-- Cuanto puede deber un chofer antes de no poder trabajar. Se cambia aqui,
-- sin desplegar la app, igual que las tarifas.
create or replace function public.limite_deuda_chofer()
 returns numeric language sql immutable set search_path to ''
as $function$ select 20.00::numeric $function$;

create or replace function public.saldo_chofer(p_conductor_id uuid default null)
 returns numeric language sql stable security definer set search_path to ''
as $function$
  select coalesce(sum(m.monto), 0)::numeric
  from public.movimientos_chofer m
  where m.conductor_id = coalesce(p_conductor_id, auth.uid())
    -- La funcion es `definer` y se salta RLS, asi que el limite va aqui.
    and (coalesce(p_conductor_id, auth.uid()) = auth.uid()
         or public.es_administrativo());
$function$;

revoke execute on function public.limite_deuda_chofer() from anon, public;
revoke execute on function public.saldo_chofer(uuid) from anon, public;
grant execute on function public.limite_deuda_chofer() to authenticated;
grant execute on function public.saldo_chofer(uuid) to authenticated;

-- Ver 2026-09-02-cobrar-comision-efectivo.sql para el enganche con
-- finalizar_viaje() y el bloqueo por deuda.
