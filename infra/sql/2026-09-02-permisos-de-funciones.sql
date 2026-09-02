-- Permisos de ejecución de las funciones de Ride
-- ------------------------------------------------------------------------
-- Dos arreglos que salieron al contrastar docs/API.md contra la base.
-- Ninguno cambia lo que hacen las funciones: solo quién puede llamarlas.
--
-- Se aplica con:
--   supabase db push
-- o pegándolo entero en el editor SQL del proyecto.


-- 1. El superadministrador no podía prepararse como chofer
-- ------------------------------------------------------------------------
-- `preparar_chofer_superadmin` solo tenía EXECUTE para `postgres` y
-- `service_role`, así que la llamada de la app rebotaba siempre con 42501.
-- La app se lo traga en silencio (driver_home_screen.dart:108), de modo que
-- no se rompía nada visible: el superadministrador simplemente seguía viendo
-- el bloqueo de cuenta no aprobada.
--
-- El grant no abre nada. La función comprueba el rol por dentro y levanta
-- 42501 igual si quien llama no es superadmin.

grant execute on function public.preparar_chofer_superadmin() to authenticated;


-- 2. Funciones `security definer` concedidas a `anon`
-- ------------------------------------------------------------------------
-- Ocho funciones que escriben en la base seguían siendo ejecutables por una
-- sesión sin autenticar. Hoy no son explotables —todas empiezan comprobando
-- `auth.uid()` o `es_administrativo()` y rebotan con 28000 o 42501—, pero el
-- permiso sobra: una comprobación dentro de la función es la segunda barrera,
-- no la primera.
--
-- El `revoke` va sobre `public` además de sobre `anon` porque `anon` hereda de
-- `public`: si el permiso hubiese llegado por ahí, revocárselo solo a `anon`
-- no habría servido de nada. Aquí el grant era explícito, pero dejarlo escrito
-- así evita que el próximo que lo lea repita la trampa.

revoke execute on function public.solicitar_viaje(
  double precision, double precision, text,
  double precision, double precision, text,
  uuid, text, text[], numeric, text, text, text
) from anon, public;

revoke execute on function public.avanzar_viaje(uuid, text) from anon, public;

revoke execute on function public.enviar_mensaje(uuid, text) from anon, public;

revoke execute on function public.marcar_mensajes_leidos(uuid) from anon, public;

revoke execute on function public.registrar_vehiculo(
  text, text, text, integer, text, uuid, text
) from anon, public;

revoke execute on function public.abrir_ticket(text, text, text, uuid)
  from anon, public;

revoke execute on function public.responder_ticket(uuid, text, text)
  from anon, public;

revoke execute on function public.ganancias_conductor() from anon, public;

-- Función de trigger. No la expone PostgREST —rechaza lo que devuelve
-- `trigger`—, pero las otras tres funciones de trigger de este esquema solo
-- tienen `service_role` y disparan sin problema: el permiso se comprueba al
-- crear el trigger, no cada vez que se dispara.
revoke execute on function public.generar_codigo_viaje() from anon, public;


-- Comprobación
-- ------------------------------------------------------------------------
-- Después de aplicarlo, esto no debe devolver ninguna fila:
--
--   select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace,
--        lateral aclexplode(p.proacl) a
--   where n.nspname = 'public'
--     and p.prosecdef
--     and a.privilege_type = 'EXECUTE'
--     and pg_get_userbyid(a.grantee) = 'anon';
