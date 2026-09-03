-- Un chofer no se aprueba a si mismo
-- ------------------------------------------------------------------------
-- Las politicas de `conductores`, `vehiculos` y `documentos_conductor` eran
-- `for all ... with check (auth.uid() = id)`. Leidas rapido parecen correctas
-- —«cada quien toca lo suyo»— y lo que dejaban abierto es esto, comprobado
-- contra la base real con una sesion de chofer normal:
--
--   update conductores set estado_aprobacion = 'aprobado' where id = <suyo>;
--   update documentos_conductor set estado = 'aprobado' where conductor_id = <suyo>;
--   update vehiculos set categoria = 'xl' where conductor_id = <suyo>;
--
-- Las tres pasaban. Es decir: cualquiera con la app instalada podia saltarse
-- la revision entera, darse por aprobado y cobrar tarifa de camioneta con un
-- auto normal. No hace falta ni descompilar el APK; PostgREST acepta el
-- `update` con el token de sesion.
--
-- El fallo no es de las politicas, es de la idea: RLS decide QUE FILAS ve
-- alguien, no QUE COLUMNAS puede escribir. Para lo segundo estan los permisos
-- por columna, que es lo que se usa aqui.

-- 1. `conductores`: el chofer solo mueve su interruptor de disponibilidad
-- ------------------------------------------------------------------------
-- Ponerse en linea y salir de linea es lo unico que decide el chofer sobre su
-- propia fila. La aprobacion, la calificacion y la posicion las escriben
-- funciones `security definer`, que corren como su dueño y no dependen de este
-- permiso.
revoke insert, update, delete on public.conductores from authenticated;
grant update (disponible) on public.conductores to authenticated;

-- 2. `documentos_conductor` y `vehiculos`: solo por funcion
-- ------------------------------------------------------------------------
-- `registrar_documento`, `registrar_vehiculo` y `activar_vehiculo` son
-- `security definer` y siguen funcionando igual. Lo que desaparece es la via
-- directa, que era la que no validaba nada.
revoke insert, update, delete on public.documentos_conductor from authenticated;
revoke insert, update, delete on public.vehiculos from authenticated;

-- 3. Respaldo: aunque un dia alguien vuelva a abrir el permiso
-- ------------------------------------------------------------------------
-- Los `grant` de arriba son la puerta; esto es el cerrojo. Si mañana alguien
-- restituye el `update` por descuido, el estado de una aprobacion sigue sin
-- poder cambiarlo el interesado.
create or replace function public.solo_administracion_aprueba()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.estado_aprobacion is distinct from old.estado_aprobacion
     and not public.es_administrativo() then
    raise exception 'Solo la administracion aprueba conductores'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists conductores_solo_administracion_aprueba on public.conductores;
create trigger conductores_solo_administracion_aprueba
  before update on public.conductores
  for each row execute function public.solo_administracion_aprueba();

create or replace function public.solo_administracion_revisa_documentos()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.estado is distinct from old.estado and not public.es_administrativo() then
    raise exception 'Solo la administracion revisa documentos'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists documentos_solo_administracion_revisa on public.documentos_conductor;
create trigger documentos_solo_administracion_revisa
  before update on public.documentos_conductor
  for each row execute function public.solo_administracion_revisa_documentos();


-- Comprobacion
-- ------------------------------------------------------------------------
-- Con la sesion de un chofer cualquiera, las tres tienen que rebotar:
--
--   begin;
--   select set_config('request.jwt.claims', '{"sub":"<chofer>","role":"authenticated"}', true);
--   set local role authenticated;
--   update public.conductores set estado_aprobacion = 'aprobado' where id = '<chofer>';
--   rollback;
--
-- Y `update public.conductores set disponible = true` tiene que seguir
-- funcionando: es lo que usa el boton de ponerse en linea.
