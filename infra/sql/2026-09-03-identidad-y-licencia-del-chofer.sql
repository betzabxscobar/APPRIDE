-- Cedula, codigo dactilar y tipo de licencia
-- ------------------------------------------------------------------------
-- Hasta ahora de la identidad de un chofer solo habia fotos: la cedula y la
-- licencia eran dos imagenes en un bucket. Nadie guardaba el numero, asi que
-- no se podia comprobar nada, ni cruzar dos cuentas de la misma persona, ni
-- saber que licencia tiene.
--
-- Tres cosas nuevas, y las tres se validan en la base:
--
-- 1. **Cedula**, con su digito verificador. El algoritmo del Registro Civil es
--    publico y se puede comprobar aqui: una cedula inventada no entra.
-- 2. **Codigo dactilar**, el que va al reverso de la cedula. Es lo que pide
--    cualquier tramite en Ecuador para confirmar que quien dice ser el dueño
--    de esa cedula la tiene en la mano. Su formato es fijo.
-- 3. **Tipo de licencia**, que decide que puede conducir. Sin esto, un chofer
--    con licencia B —particular, la de cualquiera— podia registrar una
--    camioneta y cobrar viajes.
--
-- Lo que esto NO hace: comprobar contra el Registro Civil. No hay una API
-- publica para eso. Lo que se puede hacer sin ella es que un numero mal
-- copiado o inventado no pase, y eso si se hace.

-- 1. Cedula ecuatoriana
-- ------------------------------------------------------------------------
create or replace function public.cedula_ecuatoriana_valida(p_cedula text)
 returns boolean language plpgsql immutable set search_path to ''
as $function$
declare
  v text := regexp_replace(coalesce(p_cedula, ''), '[^0-9]', '', 'g');
  v_provincia int;
  v_suma int := 0;
  v_digito int;
  i int;
begin
  if length(v) <> 10 then return false; end if;

  -- Los dos primeros son la provincia: 01 a 24, mas el 30 de los ecuatorianos
  -- registrados en el exterior.
  v_provincia := substr(v, 1, 2)::int;
  if not (v_provincia between 1 and 24 or v_provincia = 30) then
    return false;
  end if;

  -- El tercero menor que 6 es persona natural. El 6 es sector publico y el 9
  -- sociedades: son RUC, no cedulas, y un chofer es una persona.
  if substr(v, 3, 1)::int > 5 then return false; end if;

  -- Modulo 10: se duplican las posiciones impares y al que pasa de 9 se le
  -- restan 9. Es el mismo algoritmo que imprime el Registro Civil.
  for i in 1..9 loop
    v_digito := substr(v, i, 1)::int;
    if i % 2 = 1 then
      v_digito := v_digito * 2;
      if v_digito > 9 then v_digito := v_digito - 9; end if;
    end if;
    v_suma := v_suma + v_digito;
  end loop;

  return (10 - (v_suma % 10)) % 10 = substr(v, 10, 1)::int;
end;
$function$;

-- 2. Codigo dactilar
-- ------------------------------------------------------------------------
-- El del reverso de la cedula: una letra, cuatro digitos, otra letra y cuatro
-- digitos (V1234I5678). Diez caracteres, ni uno mas.
create or replace function public.dactilar_valido(p_codigo text)
 returns boolean language sql immutable set search_path to ''
as $function$
  select upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'))
         ~ '^[A-Z][0-9]{4}[A-Z][0-9]{4}$';
$function$;

-- 3. Las columnas
-- ------------------------------------------------------------------------
alter table public.conductores
  add column if not exists cedula              text,
  add column if not exists codigo_dactilar     text,
  add column if not exists licencia_tipo       text,
  add column if not exists licencia_caduca_el  date;

comment on column public.conductores.cedula is
  'Numero de cedula, solo digitos. Validado con el digito verificador.';
comment on column public.conductores.codigo_dactilar is
  'El del reverso de la cedula. Confirma que quien se registra la tiene en la mano.';
comment on column public.conductores.licencia_tipo is
  'Tipo ANT: A, A1, B, C, C1, D, D1, E, E1, F o G. Decide que categorias puede conducir.';

alter table public.conductores drop constraint if exists conductores_cedula_valida;
alter table public.conductores add constraint conductores_cedula_valida
  check (cedula is null or public.cedula_ecuatoriana_valida(cedula));

alter table public.conductores drop constraint if exists conductores_dactilar_valido;
alter table public.conductores add constraint conductores_dactilar_valido
  check (codigo_dactilar is null or public.dactilar_valido(codigo_dactilar));

alter table public.conductores drop constraint if exists conductores_licencia_tipo_check;
alter table public.conductores add constraint conductores_licencia_tipo_check
  check (licencia_tipo is null or licencia_tipo in
         ('A','A1','B','C','C1','D','D1','E','E1','F','G'));

-- Una cedula, un chofer. Dos cuentas con la misma cedula es la forma mas
-- barata de volver despues de que te expulsen.
create unique index if not exists conductores_cedula_unica
  on public.conductores (cedula) where cedula is not null;

-- 4. Que licencia habilita que categoria
-- ------------------------------------------------------------------------
-- En una tabla y no en un `case` dentro de una funcion, por lo mismo que las
-- tarifas: esto lo cambia una resolucion de la ANT, no un despliegue.
create table if not exists public.licencias_por_categoria (
  categoria  text primary key references public.categorias_vehiculo(id) on delete cascade,
  licencias  text[] not null check (cardinality(licencias) > 0),
  nota       text
);

insert into public.licencias_por_categoria (categoria, licencias, nota) values
  ('moto',     array['A','A1'],  'Motocicletas. A1 cubre tricimotos y cuadrones.'),
  ('estandar', array['C'],       'Transporte comercial de pasajeros: licencia profesional.'),
  ('confort',  array['C'],       'Transporte comercial de pasajeros: licencia profesional.'),
  ('xl',       array['C','D'],   'Camionetas y vans. La D es la de transporte publico de pasajeros.')
on conflict (categoria) do update
  set licencias = excluded.licencias, nota = excluded.nota;

alter table public.licencias_por_categoria enable row level security;

create policy licencias_por_categoria_lectura
  on public.licencias_por_categoria for select to authenticated using (true);
create policy licencias_por_categoria_escribe_administracion
  on public.licencias_por_categoria for all to authenticated
  using (public.es_administrativo()) with check (public.es_administrativo());

create or replace function public.licencia_habilita(p_licencia text, p_categoria text)
 returns boolean language sql stable set search_path to ''
as $function$
  select exists (
    select 1 from public.licencias_por_categoria l
    where l.categoria = p_categoria
      and upper(coalesce(p_licencia, '')) = any (l.licencias)
  );
$function$;

-- 5. Registrar la identidad
-- ------------------------------------------------------------------------
create or replace function public.registrar_identidad_chofer(
  p_cedula text,
  p_codigo_dactilar text,
  p_licencia_tipo text,
  p_licencia_caduca_el date)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_cedula text := regexp_replace(coalesce(p_cedula, ''), '[^0-9]', '', 'g');
  v_dactilar text := upper(regexp_replace(coalesce(p_codigo_dactilar, ''), '\s', '', 'g'));
  v_licencia text := upper(trim(coalesce(p_licencia_tipo, '')));
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesion' using errcode = '28000';
  end if;

  if not public.cedula_ecuatoriana_valida(v_cedula) then
    raise exception 'Esa cedula no es valida. Revisa los diez digitos.'
      using errcode = 'check_violation';
  end if;

  if not public.dactilar_valido(v_dactilar) then
    raise exception 'El codigo dactilar va como en el reverso de tu cedula: una letra, cuatro numeros, una letra y cuatro numeros.'
      using errcode = 'check_violation';
  end if;

  if v_licencia not in ('A','A1','B','C','C1','D','D1','E','E1','F','G') then
    raise exception 'Ese tipo de licencia no existe' using errcode = 'check_violation';
  end if;

  if p_licencia_caduca_el is null or p_licencia_caduca_el <= current_date then
    raise exception 'La licencia esta vencida o le falta la fecha de caducidad'
      using errcode = 'check_violation';
  end if;

  -- La cedula de otro no se puede reclamar. El indice unico tambien lo impide,
  -- pero su mensaje no lo entiende nadie.
  if exists (select 1 from public.conductores
             where cedula = v_cedula and id <> v_uid) then
    raise exception 'Esa cedula ya esta registrada en otra cuenta'
      using errcode = 'unique_violation';
  end if;

  insert into public.conductores (id, cedula, codigo_dactilar, licencia_tipo, licencia_caduca_el)
  values (v_uid, v_cedula, v_dactilar, v_licencia, p_licencia_caduca_el)
  on conflict (id) do update
    set cedula = excluded.cedula,
        codigo_dactilar = excluded.codigo_dactilar,
        licencia_tipo = excluded.licencia_tipo,
        licencia_caduca_el = excluded.licencia_caduca_el;
end;
$function$;

revoke execute on function public.registrar_identidad_chofer(text, text, text, date) from anon, public;
revoke execute on function public.cedula_ecuatoriana_valida(text) from anon, public;
revoke execute on function public.dactilar_valido(text) from anon, public;
revoke execute on function public.licencia_habilita(text, text) from anon, public;
grant execute on function public.registrar_identidad_chofer(text, text, text, date) to authenticated;
grant execute on function public.cedula_ecuatoriana_valida(text) to authenticated;
grant execute on function public.dactilar_valido(text) to authenticated;
grant execute on function public.licencia_habilita(text, text) to authenticated;


-- Comprobacion
-- ------------------------------------------------------------------------
--   select public.cedula_ecuatoriana_valida('1710034065');  -- true
--   select public.cedula_ecuatoriana_valida('1710034066');  -- false, digito
--   select public.cedula_ecuatoriana_valida('9910034065');  -- false, provincia
--   select public.dactilar_valido('V1234I5678');            -- true
--   select public.licencia_habilita('B', 'estandar');       -- false
--   select public.licencia_habilita('C', 'estandar');       -- true
