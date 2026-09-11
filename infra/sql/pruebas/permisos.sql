-- Permisos que tienen que cumplirse en la base de Ride
-- ---------------------------------------------------------------------------
-- Devuelve una fila por cada regla rota; vacio = todo en orden. Solo lee, asi
-- que se puede pasar en produccion. Hay que pasarla despues de cada migracion
-- (SQL Editor de Supabase, o `psql -f`).
--
-- Nacio de la auditoria del 2026-09-11: dos migraciones habian reabierto
-- permisos sin que nadie se enterara, y dos funciones dejaban localizar a los
-- choferes. Si se anade una RPC que la app o la web llaman, va en
-- `rpc_clientes`; si se cierra una a proposito, en `cerradas`.

with
rpc_clientes(nombre) as (values
  ('abrir_ticket'), ('aceptar_viaje'), ('activar_vehiculo'), ('avanzar_viaje'), ('cancelar_viaje'),
  ('confirmar_pago_recibido'), ('cotizar_categorias'), ('cotizar_viaje'), ('cuentas_del_chofer'),
  ('elegir_metodo_predeterminado'), ('elegir_mis_zonas'), ('eliminar_cuenta_bancaria'), ('enviar_mensaje'),
  ('finalizar_viaje'), ('ganancias_conductor'), ('limpiar_direcciones_viejas'), ('marcar_mensajes_leidos'),
  ('marcar_notificaciones_leidas'), ('mi_suscripcion'), ('mis_zonas'), ('papeles_que_faltan_chofer'),
  ('preparar_chofer_superadmin'), ('quiero_ser_chofer'), ('recordar_direccion'), ('registrar_cuenta_bancaria'),
  ('registrar_documento'), ('registrar_identidad_chofer'), ('registrar_metodo_pago'), ('registrar_vehiculo'),
  ('reportar_posicion'), ('reportar_transferencia'), ('responder_ticket'), ('revisar_conductor'),
  ('revisar_documento'), ('solicitar_viaje'), ('solicitudes_abiertas')
),
cerradas(nombre) as (values
  ('conductores_cercanos'), ('conductores_en_celdas'), ('saldo_chofer'),
  ('current_user_must_change_password'), ('confirmar_pago_efectivo'), ('suscripcion_vigente')
),
funciones as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.prorettype
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
)
select 'La app o la web la llaman y no se puede ejecutar con sesion' as regla, r.nombre as objeto
from rpc_clientes r
where not exists (select 1 from funciones f
                  where f.proname = r.nombre and has_function_privilege('authenticated', f.oid, 'execute'))

union all
select 'Se puede ejecutar sin sesion', f.proname
from funciones f
where f.prorettype <> 'trigger'::regtype and has_function_privilege('anon', f.oid, 'execute')

union all
select 'Debia estar cerrada', f.proname
from funciones f join cerradas c on c.nombre = f.proname
where has_function_privilege('authenticated', f.oid, 'execute')

union all
select 'Disparador security definer ejecutable por RPC', f.proname
from funciones f
where f.prosecdef and f.prorettype = 'trigger'::regtype
  and (has_function_privilege('authenticated', f.oid, 'execute') or has_function_privilege('anon', f.oid, 'execute'))

union all
select 'security definer sin search_path', f.proname
from funciones f
where f.prosecdef
  and not exists (select 1 from unnest(coalesce(f.proconfig, '{}'::text[])) cfg where cfg like 'search_path=%')

union all
select 'Tabla sin RLS', c.relname
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity

union all
select 'Vista sin security_invoker (se salta el RLS)', c.relname
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
  and coalesce(array_to_string(c.reloptions, ','), '') !~ 'security_invoker=(on|true)'

union all
select 'Tabla escribible sin sesion', c.relname
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
  and (has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE')
       or has_table_privilege('anon', c.oid, 'DELETE'))

union all
select 'Los avisos de PayPal se ven desde la app', 'eventos_paypal'
where has_table_privilege('authenticated', 'public.eventos_paypal', 'SELECT')

union all
select 'Bucket privado que se sirve publico', b.id
from storage.buckets b
where b.id in ('documentos', 'comprobantes') and b.public

union all
select 'Las funciones nuevas nacerian ejecutables por cualquiera (PUBLIC)', '(global)'
where not exists (select 1 from pg_default_acl d
                  where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f' and d.defaclnamespace = 0)

union all
select 'Las funciones nuevas nacerian ejecutables sin sesion', 'public'
from pg_default_acl d
where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f'
  and d.defaclnamespace = 'public'::regnamespace
  and array_to_string(d.defaclacl, ',') ~ '(^|,)anon=';
