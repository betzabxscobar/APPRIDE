-- Multa por cancelación tardía
-- ---------------------------------------------------------------------------
-- Cancelar cuando el chofer ya está esperando en el punto le cuesta el viaje
-- hasta ahí: gasolina, tiempo y las solicitudes que no pudo tomar mientras
-- venía. Hasta ahora eso salía gratis.
--
-- Las tres decisiones son de Diego, no técnicas:
--   · un dólar fijo, por debajo de la carrera mínima ($1.50);
--   · solo en CONDUCTOR_EN_ORIGEN, cuando el chofer ya llegó y espera;
--   · repartido como un viaje, 85/15, con el porcentaje de LA TARIFA DEL
--     VIAJE y no el de hoy.
--
-- Solo se multa al PASAJERO. Si el que cancela es el chofer no se cobra nada:
-- cancelar es justamente lo que tiene que hacer cuando el pasajero no aparece.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. Cuánto
-- ---------------------------------------------------------------------------
create or replace function public.multa_cancelacion_tardia()
returns numeric language sql immutable set search_path = ''
as $$ select 1.00::numeric $$;


-- 2. `pagos` tiene que admitir una multa
-- ---------------------------------------------------------------------------
-- El cargo va a `pagos` y no a una tabla aparte porque es dinero que el
-- pasajero debe, igual que un viaje: mismo sitio, mismo estado, misma
-- pasarela el día que DeUna esté conectado.
alter table public.pagos drop constraint if exists pagos_tipo_check;
alter table public.pagos add constraint pagos_tipo_check
  check (tipo = any (array['pago'::text, 'reembolso'::text, 'reintento'::text, 'multa'::text]));


-- 3. Cancelar tarde cuesta
-- ---------------------------------------------------------------------------
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
  v_pasajero uuid;
  v_conductor uuid;
  v_tarifa uuid;
  v_multa numeric;
  v_pct numeric;
  v_abono numeric;
begin
  select estado, pasajero_id, conductor_id, tarifa_id
    into v_actual, v_pasajero, v_conductor, v_tarifa
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

  -- La multa solo cae si el chofer ya habia llegado al punto Y es el pasajero
  -- quien cancela. Un chofer que cancela porque el pasajero no aparece no
  -- puede cobrarle por su propia cancelacion.
  if v_actual = 'CONDUCTOR_EN_ORIGEN' and v_uid = v_pasajero then
    v_multa := public.multa_cancelacion_tardia();

    if v_multa > 0 then
      insert into public.pagos (viaje_id, monto, tipo, estado)
      values (p_viaje_id, v_multa, 'multa', 'pendiente');

      -- Al chofer se le abona ya: el tiempo lo perdio hoy, no el dia que se
      -- cobre. Se usa el porcentaje de la tarifa del viaje, como en el resto
      -- del sistema.
      if v_conductor is not null then
        select porcentaje_conductor into v_pct
        from public.tarifas where id = v_tarifa;

        v_abono := round(v_multa * coalesce(v_pct, 0.85), 2);

        if v_abono > 0 then
          insert into public.movimientos_chofer
            (conductor_id, viaje_id, tipo, monto, concepto)
          values (v_conductor, p_viaje_id, 'ajuste', v_abono,
                  'Multa por cancelacion con el chofer ya en el punto')
          on conflict do nothing;
        end if;
      end if;
    end if;
  end if;
end;
$function$;


-- 4. Que la multa se vea en la vista
-- ---------------------------------------------------------------------------
-- `monto_cobrado` y `pago_estado` contaban solo 'pago' y 'reintento'. Sin
-- esto, un viaje cancelado con multa saldria como si no debiera nada.
--
-- El `with (security_invoker = on)` NO se puede omitir: `create or replace
-- view` sin clausula `with` deja las opciones en blanco, y una vista sin
-- security_invoker corre con los permisos de su dueno (postgres) saltandose
-- el RLS de `viajes`. Ya paso una vez.
create or replace view public.viajes_detalle
with (security_invoker = on) as
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
    v.desvio_detectado,
    COALESCE(cobro.multa, 0::numeric) AS multa
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
                    WHEN p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text, 'multa'::text])) THEN p.monto
                    WHEN p.estado = 'completado'::text AND p.tipo = 'reembolso'::text THEN - p.monto
                    ELSE 0::numeric
                END) AS monto_cobrado,
                sum(
                CASE
                    WHEN p.tipo = 'multa'::text THEN p.monto
                    ELSE 0::numeric
                END) AS multa,
                CASE
                    WHEN bool_or(p.estado = 'completado'::text AND (p.tipo = ANY (ARRAY['pago'::text, 'reintento'::text, 'multa'::text]))) THEN 'completado'::text
                    WHEN bool_or(p.estado = 'pendiente'::text) THEN 'pendiente'::text
                    WHEN count(*) > 0 THEN 'fallido'::text
                    ELSE NULL::text
                END AS estado
           FROM pagos p
          WHERE p.viaje_id = v.id) cobro ON true;

alter view public.viajes_detalle set (security_invoker = on);


-- 5. Permisos
-- ---------------------------------------------------------------------------
revoke execute on function public.multa_cancelacion_tardia() from public, anon;
grant execute on function public.multa_cancelacion_tardia() to authenticated;
