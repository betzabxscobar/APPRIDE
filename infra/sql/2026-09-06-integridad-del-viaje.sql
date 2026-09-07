-- Integridad del viaje: llegada, cobro y cancelación
-- ---------------------------------------------------------------------------
-- Tres huecos que salieron al revisar el cierre de un viaje.
--
-- 1. `finalizar_viaje` no miraba DÓNDE estaba el chofer. Podía aceptar el
--    viaje, arrancarlo con el código del pasajero y cerrarlo en el mismo
--    portal de origen, cobrando la tarifa entera del recorrido que no hizo.
--
-- 2. El pago en efectivo nacía 'completado'. Nadie decía que hubiera recibido
--    el dinero: se daba por hecho. Ahora nace 'pendiente' y lo confirma el
--    chofer, que es quien sabe si el pasajero pagó.
--
-- 3. Cancelar en pleno viaje YA estaba bloqueado (en `cancelar_viaje` y en el
--    trigger `validar_transicion_viaje`). Lo que faltaba era el registro: la
--    fila no guardaba quién canceló, cuándo, ni por qué, así que ante un
--    reclamo no había nada que mirar.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. Parámetros
-- ---------------------------------------------------------------------------
-- Del mismo estilo que `limite_deuda_chofer()`: un solo sitio que cambiar.

-- A qué distancia del destino se acepta que el chofer ya llegó. 300 m cubre el
-- error del GPS urbano y la manzana que a veces hay que rodear por los
-- sentidos de las calles.
create or replace function public.radio_llegada_km()
returns numeric language sql immutable set search_path = ''
as $$ select 0.30::numeric $$;

-- Cuánto puede pasarse el recorrido real sobre la línea recta origen-destino
-- antes de considerarlo un rodeo. En Quito lo normal ronda 1,3-1,4 por el
-- trazado de las calles; 2,5 deja margen de sobra y solo marca lo raro.
create or replace function public.desvio_maximo_factor()
returns numeric language sql immutable set search_path = ''
as $$ select 2.5::numeric $$;

-- Un viaje no dura segundos. Por debajo de esto, el cierre es un error de dedo
-- o un intento de cobrar sin llevar a nadie.
create or replace function public.duracion_minima_viaje_seg()
returns integer language sql immutable set search_path = ''
as $$ select 60 $$;


-- 2. Lo que hay que poder mirar después
-- ---------------------------------------------------------------------------
alter table public.viajes
  add column if not exists cancelado_por uuid references public.profiles(id),
  add column if not exists cancelado_en timestamptz,
  add column if not exists motivo_cancelacion text,
  add column if not exists distancia_recorrida_km numeric,
  add column if not exists llegada_verificada boolean,
  add column if not exists desvio_detectado boolean;

comment on column public.viajes.llegada_verificada is
  'true: el chofer cerro el viaje junto al destino. null: no habia rastro GPS y no se pudo comprobar, mirar a mano.';
comment on column public.viajes.desvio_detectado is
  'El recorrido se paso del factor sobre la linea recta origen-destino.';


-- 3. Cuánto se recorrió de verdad
-- ---------------------------------------------------------------------------
-- Suma tramo a tramo el rastro que `reportar_posicion` va dejando en
-- `ubicaciones`. No es la ruta que dio el navegador —esa no se guarda— pero sí
-- por dónde pasó el carro, que es lo que permite ver un rodeo.
create or replace function public.recorrido_km(p_viaje_id uuid)
returns numeric language sql stable set search_path = ''
as $$
  with rastro as (
    select
      latitud, longitud,
      lag(latitud)  over (order by registrado_en) as lat_previa,
      lag(longitud) over (order by registrado_en) as lng_previa
    from public.ubicaciones
    where viaje_id = p_viaje_id and tipo = 'posicion_actual'
  )
  select round(
    coalesce(sum(public.distancia_km(lat_previa, lng_previa, latitud, longitud)), 0)::numeric,
    3)
  from rastro
  where lat_previa is not null;
$$;


-- 4. Cerrar el viaje solo si se llegó
-- ---------------------------------------------------------------------------
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
  v_pasajero uuid;
  v_tarifa uuid;
  v_inicio timestamptz;
  v_dest_lat double precision;
  v_dest_lng double precision;
  v_org_lat double precision;
  v_org_lng double precision;
  v_lat double precision;
  v_lng double precision;
  v_al_destino numeric;
  v_recorrido numeric;
  v_recta numeric;
  v_verificada boolean;
  v_desvio boolean := false;
begin
  select tarifa_estimada, pasajero_id, tarifa_id, fecha_inicio
    into v_estimada, v_pasajero, v_tarifa, v_inicio
  from public.viajes
  where id = p_viaje_id and conductor_id = v_uid and estado = 'EN_CURSO';

  if v_estimada is null then
    raise exception 'Solo el conductor puede cerrar un viaje en curso'
      using errcode = '42501';
  end if;

  if v_inicio is not null
     and now() - v_inicio < make_interval(secs => public.duracion_minima_viaje_seg()) then
    raise exception 'El viaje acaba de empezar. Espera a llegar al destino.'
      using errcode = 'check_violation';
  end if;

  select latitud, longitud into v_dest_lat, v_dest_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'destino' limit 1;

  select latitud, longitud into v_org_lat, v_org_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'origen' limit 1;

  select latitud, longitud into v_lat, v_lng
  from public.ubicaciones
  where viaje_id = p_viaje_id and tipo = 'posicion_actual'
  order by registrado_en desc limit 1;

  if v_lat is null or v_dest_lat is null then
    -- Sin rastro no hay con qué comprobar. Se deja cerrar —el pasajero está
    -- ahí esperando y no puede quedarse atrapado en un viaje abierto—, pero
    -- queda marcado para que administración lo revise.
    v_verificada := null;
  else
    v_al_destino := public.distancia_km(v_lat, v_lng, v_dest_lat, v_dest_lng)::numeric;

    if v_al_destino > public.radio_llegada_km() then
      raise exception
        'Todavia no estas en el destino: faltan % km. El viaje se cierra al llegar.',
        round(v_al_destino, 2)
        using errcode = 'check_violation';
    end if;

    v_verificada := true;
  end if;

  v_recorrido := public.recorrido_km(p_viaje_id);

  if v_org_lat is not null and v_dest_lat is not null then
    v_recta := public.distancia_km(v_org_lat, v_org_lng, v_dest_lat, v_dest_lng)::numeric;
    v_desvio := v_recta > 0
            and v_recorrido > v_recta * public.desvio_maximo_factor();
  end if;

  update public.viajes
  set estado = 'FINALIZADO',
      fecha_fin = now(),
      tarifa_final = v_estimada,
      distancia_recorrida_km = v_recorrido,
      llegada_verificada = v_verificada,
      desvio_detectado = v_desvio
  where id = p_viaje_id;

  select id into v_metodo
  from public.metodos_pago
  where pasajero_id = v_pasajero and predeterminado
  limit 1;

  -- Todo cobro nace pendiente, el efectivo tambien. Antes el efectivo entraba
  -- como 'completado' sin que nadie lo hubiera visto: eso no era saber que el
  -- pasajero pago, era suponerlo. Lo confirma el chofer con
  -- `confirmar_pago_efectivo`, y con el pasa la comision a su cuenta.
  insert into public.pagos (viaje_id, metodo_pago_id, monto, tipo, estado)
  values (p_viaje_id, v_metodo, v_estimada, 'pago', 'pendiente');

  return v_estimada;
end;
$function$;


-- 5. El chofer confirma que recibió el efectivo
-- ---------------------------------------------------------------------------
create or replace function public.confirmar_pago_efectivo(p_viaje_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_pago_id uuid;
  v_monto numeric;
  v_estado text;
  v_tipo text;
  v_pct numeric;
  v_comision numeric;
begin
  select p.id, p.monto, p.estado, coalesce(m.tipo, 'efectivo'), t.porcentaje_conductor
    into v_pago_id, v_monto, v_estado, v_tipo, v_pct
  from public.pagos p
  join public.viajes v on v.id = p.viaje_id
  join public.tarifas t on t.id = v.tarifa_id
  left join public.metodos_pago m on m.id = p.metodo_pago_id
  where p.viaje_id = p_viaje_id
    and v.conductor_id = v_uid
    and v.estado = 'FINALIZADO'
    and p.tipo = 'pago'
  order by p.fecha desc
  limit 1;

  if v_pago_id is null then
    raise exception 'Ese viaje no es tuyo o todavia no tiene cobro'
      using errcode = '42501';
  end if;

  if v_tipo <> 'efectivo' then
    raise exception 'Ese viaje no se paga en efectivo'
      using errcode = 'check_violation';
  end if;

  -- Confirmar dos veces no puede cobrar la comision dos veces.
  if v_estado = 'completado' then
    return;
  end if;

  update public.pagos
  set estado = 'completado', actualizado_en = now()
  where id = v_pago_id;

  -- El dinero ya lo tiene el chofer, asi que la comision pasa a ser deuda
  -- suya. Se usa el porcentaje de LA TARIFA DEL VIAJE, no el de hoy: lo ya
  -- cobrado no se recalcula si mañana cambia el reparto.
  v_comision := v_monto - round(v_monto * coalesce(v_pct, 0.85), 2);

  if v_comision > 0 then
    insert into public.movimientos_chofer
      (conductor_id, viaje_id, tipo, monto, concepto)
    values (v_uid, p_viaje_id, 'comision', -v_comision,
            'Comision del viaje cobrado en efectivo')
    on conflict do nothing;
  end if;
end;
$function$;


-- 6. Cancelar: sigue prohibido en curso, y ahora queda quién y por qué
-- ---------------------------------------------------------------------------
-- La firma cambia, así que hay que soltar la vieja: dejar las dos convertiría
-- cada `cancelar_viaje(uuid)` de la app en una llamada ambigua.
drop function if exists public.cancelar_viaje(uuid);

create or replace function public.cancelar_viaje(
  p_viaje_id uuid,
  p_motivo text default null
)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_actual public.enum_estado_viaje;
begin
  select estado into v_actual
  from public.viajes
  where id = p_viaje_id and v_uid in (pasajero_id, conductor_id);

  if v_actual is null then
    raise exception 'Ese viaje no es tuyo' using errcode = '42501';
  end if;

  -- EN_CURSO no se cancela: la persona va a bordo. Termina en FINALIZADO o no
  -- termina. El trigger `validar_transicion_viaje` lo vuelve a impedir por
  -- debajo, aunque alguien llame a otra cosa.
  if v_actual in ('EN_CURSO', 'FINALIZADO', 'CANCELADO', 'SIN_CONDUCTOR') then
    raise exception 'Este viaje ya no se puede cancelar'
      using errcode = 'check_violation';
  end if;

  update public.viajes
  set estado = 'CANCELADO',
      cancelado_por = v_uid,
      cancelado_en = now(),
      motivo_cancelacion = nullif(trim(coalesce(p_motivo, '')), '')
  where id = p_viaje_id;
end;
$function$;


-- 7. Que la app pueda verlo
-- ---------------------------------------------------------------------------
-- Las columnas nuevas viven en `viajes`, pero la app lee `viajes_detalle`.
-- Sin esto, el `select` de RideService pide columnas que la vista no tiene y
-- revienta con un 400. Van al final: `create or replace view` solo admite
-- columnas añadidas después de las que ya estaban.
create or replace view public.viajes_detalle as
 SELECT v.id,
    v.estado,
    v.pasajero_id,
    v.conductor_id,
    v.vehiculo_id,
    v.tarifa_estimada,
    v.tarifa_final,
    v.fecha_solicitud,
    v.fecha_inicio,
    v.fecha_fin,
    t.nombre AS tarifa_nombre,
    pp.full_name AS pasajero_nombre,
    pp.phone AS pasajero_telefono,
        CASE
            WHEN v.conductor_id IS NULL THEN NULL::text
            ELSE COALESCE(NULLIF(TRIM(BOTH FROM pc.full_name), ''::text), pc.email, 'Conductor asignado'::text)
        END AS conductor_nombre,
    pc.phone AS conductor_telefono,
    c.calificacion_promedio AS conductor_calificacion,
    ve.placa AS vehiculo_placa,
    ve.marca AS vehiculo_marca,
    ve.modelo AS vehiculo_modelo,
    ve.color AS vehiculo_color,
    o.latitud AS origen_lat,
    o.longitud AS origen_lng,
    o.direccion_texto AS origen_texto,
    d.latitud AS destino_lat,
    d.longitud AS destino_lng,
    d.direccion_texto AS destino_texto,
    COALESCE(cobro.monto_cobrado, 0::numeric) AS monto_cobrado,
    cobro.estado AS pago_estado,
    o.referencia AS origen_referencia,
    d.referencia AS destino_referencia,
    v.categoria,
    cat.nombre AS categoria_nombre,
    cat.icono AS categoria_icono,
    v.cancelado_por,
    v.cancelado_en,
    v.motivo_cancelacion,
    v.distancia_recorrida_km,
    v.llegada_verificada,
    v.desvio_detectado
   FROM viajes v
     JOIN tarifas t ON t.id = v.tarifa_id
     JOIN profiles pp ON pp.id = v.pasajero_id
     LEFT JOIN categorias_vehiculo cat ON cat.id = v.categoria
     LEFT JOIN profiles pc ON pc.id = v.conductor_id
     LEFT JOIN conductores c ON c.id = v.conductor_id
     LEFT JOIN vehiculos ve ON ve.id = v.vehiculo_id
     LEFT JOIN ubicaciones o ON o.viaje_id = v.id AND o.tipo = 'origen'::text
     LEFT JOIN ubicaciones d ON d.viaje_id = v.id AND d.tipo = 'destino'::text
     LEFT JOIN LATERAL ( SELECT sum(
                CASE
                    WHEN p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text])) THEN p.monto
                    WHEN p.estado = 'completado'::text AND p.tipo = 'reembolso'::text THEN - p.monto
                    ELSE 0::numeric
                END) AS monto_cobrado,
                CASE
                    WHEN bool_or(p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text]))) THEN 'completado'::text
                    WHEN bool_or(p.estado = 'pendiente'::text) THEN 'pendiente'::text
                    WHEN count(*) > 0 THEN 'fallido'::text
                    ELSE NULL::text
                END AS estado
           FROM pagos p
          WHERE p.viaje_id = v.id) cobro ON true;


-- 8. Permisos
-- ---------------------------------------------------------------------------
-- El `revoke` va sobre `public` además de sobre `anon`, porque `anon` hereda
-- de `public` y revocárselo solo a `anon` no serviría de nada.

revoke execute on function public.cancelar_viaje(uuid, text) from public, anon;
revoke execute on function public.confirmar_pago_efectivo(uuid) from public, anon;
revoke execute on function public.recorrido_km(uuid) from public, anon;

grant execute on function public.cancelar_viaje(uuid, text) to authenticated;
grant execute on function public.confirmar_pago_efectivo(uuid) to authenticated;
grant execute on function public.recorrido_km(uuid) to authenticated;
