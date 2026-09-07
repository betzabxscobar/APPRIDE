-- Las solicitudes abiertas que ve el chofer
-- ---------------------------------------------------------------------------
-- La lista de oportunidades salía SIEMPRE vacía para cualquier chofer que no
-- fuera superadministrador. Se descubrió probando la difusión por zonas de
-- punta a punta, con el RLS puesto y con una cuenta de rol `driver`.
--
-- El motivo no era la zona. `viajes_detalle` es `security_invoker`, así que el
-- RLS se aplica a todas sus tablas con los permisos de quien consulta:
--
--   · la fila de `viajes` sí la ve, la política de difusión se la deja;
--   · el perfil del pasajero NO —`can_view_role('passenger')` es false para un
--     chofer— y la vista hace un `join` interno con él;
--   · las `ubicaciones` tampoco, porque solo las ven los participantes y en una
--     solicitud abierta todavía no lo es.
--
-- El `join` interno con `profiles` borraba la fila entera. Comprobado: mismo
-- viaje, 1 fila en `viajes` y 0 en `viajes_detalle`.
--
-- Esta función devuelve solo lo que el chofer necesita para decidir y aplica
-- por dentro las mismas condiciones que la política. Es `security definer` a
-- propósito: se salta el RLS de las tablas de apoyo, no el filtro. De paso
-- **no** devuelve el nombre ni el teléfono del pasajero: eso no le hace falta
-- para decidir, y solo debe llegarle cuando acepte.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.

create or replace function public.solicitudes_abiertas()
returns table (
  id uuid,
  estado text,
  pasajero_id uuid,
  tarifa_estimada numeric,
  tarifa_nombre text,
  fecha_solicitud timestamptz,
  origen_lat double precision,
  origen_lng double precision,
  origen_texto text,
  origen_referencia text,
  destino_lat double precision,
  destino_lng double precision,
  destino_texto text,
  destino_referencia text,
  categoria text,
  categoria_nombre text,
  categoria_icono text,
  gana_conductor numeric,
  distancia_km numeric,
  minutos_estimados integer,
  zona_origen text
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    v.id,
    v.estado::text,
    v.pasajero_id,
    v.tarifa_estimada,
    t.nombre,
    v.fecha_solicitud,
    o.latitud, o.longitud, o.direccion_texto, o.referencia,
    d.latitud, d.longitud, d.direccion_texto, d.referencia,
    v.categoria, cat.nombre, cat.icono,
    round(v.tarifa_estimada * t.porcentaje_conductor, 2),
    round(public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)::numeric, 1),
    greatest(1, round(
      public.distancia_km(o.latitud, o.longitud, d.latitud, d.longitud)
      / public.velocidad_media_kmh() * 60)::integer),
    public.zona_de(o.latitud, o.longitud)
  from public.viajes v
  join public.tarifas t on t.id = v.tarifa_id
  left join public.categorias_vehiculo cat on cat.id = v.categoria
  left join public.ubicaciones o on o.viaje_id = v.id and o.tipo = 'origen'
  left join public.ubicaciones d on d.viaje_id = v.id and d.tipo = 'destino'
  where v.estado = 'BUSCANDO_CONDUCTOR'
    and v.conductor_id is null
    -- Las mismas condiciones que `viajes_difusion_conductores`, repetidas aquí
    -- porque al ser `definer` la política ya no las aplica sola.
    and (
      public.es_superadmin()
      or (
        public.viaje_en_mi_zona(v.id)
        and (
          public.viaje_en_mi_celda(v.id)
          or (v.celdas_difusion is null and public.viaje_esta_cerca_de_mi(v.id))
        )
      )
    )
  -- Quien pidió antes no se queda al fondo de la lista.
  order by v.fecha_solicitud;
$$;

revoke execute on function public.solicitudes_abiertas() from public, anon;
grant execute on function public.solicitudes_abiertas() to authenticated;
