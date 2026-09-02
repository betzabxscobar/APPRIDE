# Tarifas de Ride

Las calcula Postgres (`public.cotizar_viaje`) y ahí se quedan: el cliente se
puede manipular, así que no puede ser quien diga cuánto cuesta un viaje.

## Los valores

**Vigentes desde el 2026-09-02.**

| | Arranque | Por km | Por minuto | Carrera mínima |
|---|---|---|---|---|
| **Estándar** (resto del día) | 0,35 | 0,25 | 0,07 | 1,20 |
| **Hora pico mañana** (06:00–08:59, L–V) | 0,38 | 0,27 | 0,08 | 1,30 |
| **Hora pico tarde** (16:00–19:59, L–V) | 0,38 | 0,27 | 0,08 | 1,30 |
| **Nocturna** (22:00–04:59) | 0,40 | 0,29 | 0,08 | 1,38 |

### De dónde salen

De una medición real, no de una tabla de referencia. La regla es **quedar por
debajo de DiDi**, que era el más barato de los dos que se compararon.

Trayecto medido: parada **El Florón** (Av. 10 de Agosto) → **Universidad
Central del Ecuador**. 4,4 km, 7 minutos.

| | Precio |
|---|---|
| **Ride, estándar** | **1,45** |
| DiDi | 1,50 |
| Ride, hora pico | 1,57 |
| Ride, nocturna | 1,68 |
| Uber | 2,25 |

La estándar se calibra contra ese 1,45 y las otras dos salen de ahí con su
recargo: **+8 % la hora pico y +15 % la nocturna**.

> **En hora pico y de noche se pasa de DiDi.** 1,57 y 1,68 contra sus 1,50. No
> hay manera de conservar un recargo por franja y quedar debajo de DiDi a todas
> horas: o se aplana el recargo, o esas horas se pagan más. Se eligió conservar
> el recargo, porque conducir de noche y en atasco vale más.

**Qué se comparó y qué no.** DiDi y Uber se consultaron en ese momento, así que
sus números llevan dentro la demanda que hubiera. Y los 1,50 y 2,25 son de su
categoría de coche normal: en ese viaje, Confort sale en 1,89 y XL en 2,25, por
encima de DiDi a propósito, porque no compiten contra lo mismo.

> **Antes se calculaban de otra forma.** Hasta el 2026-09-02 salían de las
> tarifas referenciales de taxi de Quito con un 10 % menos. Se abandonó ese
> método porque dejaba el precio por encima de la competencia real; lo que
> manda ahora es quedar por debajo de DiDi.

### Las franjas horarias

Salen del **Pico y Placa** de Quito, que es la definición municipal de cuándo
hay congestión: **06:00–09:30 y 16:00–20:00, de lunes a viernes**. Antes la
hora pico era 06:00–09:00 inventada y no existía la de la tarde, que en Quito
es la peor.

La tabla guarda **horas enteras**, así que las medias horas hay que redondear:

| Pico y Placa | En `tarifas` | Diferencia |
|---|---|---|
| 06:00–09:30 | 06:00–08:59 | se queda 31 min corta |
| 16:00–20:00 | 16:00–19:59 | clava el horario |

En la mañana se recorta en vez de estirar: cobrar hora pico a las 09:45 —que
es lo que pasaba antes— es cobrar de más fuera de la congestión, y entre
quedarse corto y pasarse, mejor corto.

**Solo de lunes a viernes.** El Pico y Placa no rige el fin de semana, así que
las dos franjas pico tampoco: un domingo a las 17:00 se cobra tarifa estándar.
Lo lleva la columna `dias` de `tarifas`, un arreglo de días ISO —1 es lunes y
7 domingo—, y `tarifa_vigente()` la comprueba con `extract(isodow ...)`. En
**null** significa «todos los días», que es como están la estándar y la
nocturna.

Repartido por semana: 15 horas de pico de mañana, 20 de pico de tarde, 49 de
nocturna y 84 de estándar. Suman las 168 de la semana.

> **No poner `dias` en una franja que cruza medianoche.** A la 01:00 del
> sábado el día ya es sábado, así que una nocturna limitada a `{1,2,3,4,5}`
> dejaría de aplicar a mitad de la madrugada del viernes y el precio cambiaría
> solo. Por eso la nocturna se queda en null.

## La formula

```
total = max( (arranque + por_km x km) x factor_del_vehiculo ,
             carrera_minima x factor_del_vehiculo )
```

> **`costo_por_minuto` no entra en la cuenta.** La columna existe y se guarda,
> pero `cotizar_viaje` no la usa: representa tiempo de espera, y una cotizacion
> hecha antes de salir no sabe cuantos minutos va a estar el auto detenido. Los
> `minutos_estimados` que devuelve la funcion son para enseñarlos, no para
> cobrarlos. Cambiar esa columna no cambia lo que paga nadie.

Los factores por tipo de vehiculo —moto 0,80, estandar 1,00, confort 1,45 y
XL 1,80— multiplican tanto el precio como la carrera minima, asi que la tabla
de arriba es la de **Estandar** y el resto sale de ahi.

## El reparto

Cada tarifa lleva `porcentaje_conductor`, hoy **0,85**: el chofer se lleva el
85 % de lo que paga el pasajero y el 15 % restante es comisión de la app.

`cotizar_viaje` devuelve ya repartido `gana_conductor` y `comision_app`, para
que ni la app ni el cliente tengan que multiplicar por su cuenta.

**Bajar la comisión no abarata el viaje.** El pasajero paga lo mismo; lo que
cambia es quién se lo lleva.

### Por qué 15 %

Se empezó en 40 % y se bajó el 2026-08-27. Razones:

- **El cuello de botella son los choferes**, no los pasajeros. Sin choferes no
  hay servicio, y lo escaso hay que pagarlo bien.
- **El coste real por carrera hoy es casi nulo**: Supabase en plan gratuito,
  OpenStreetMap y el OSRM de demostración. La comisión no cubre operación,
  financia crecimiento que aún no existe.
- **inDrive ya está asentado en Quito con 10–15 %.** Al chofer le da igual la
  marca: compara lo que se lleva.

Sobre un trayecto real de Quito de 5,92 km ($4,31):

| Comisión | Chofer | App |
|---|---|---|
| 40 % | 2,59 | 1,72 |
| 20 % | 3,45 | 0,86 |
| **15 %** | **3,66** | **0,65** |

**Cuándo subirla.** El 20 % es un techo razonable una vez haya choferes fieles y
costes de verdad (hospedaje propio de OSRM, teselas de pago, soporte, y el 3–4 %
que se lleva la pasarela si se cobra con tarjeta). Subir antes de eso es
regalarle choferes a la competencia.

Se cambia con una línea, sin desplegar la app:

```sql
update public.tarifas set porcentaje_conductor = 0.80;  -- comision del 20 %
```

Es una columna **por tarifa**, así que también se puede dejar más baja de noche
para que salgan choferes en la franja donde escasean.

## Qué tarifa se aplica

La elige el **servidor** con `public.tarifa_vigente()`, según la hora local de
Ecuador (`America/Guayaquil`). La franja que cubre la hora gana; si ninguna la
cubre, se usa la que no tiene franja. Si dos coincidieran, gana la más cara.

> **Los dos extremos entran, y solo cuenta la hora entera.** La comparación es
> un `between` sobre `extract(hour ...)`, así que `hora_hasta = 8` cubre hasta
> las **08:59**, no hasta las 08:00. Por eso las franjas se escriben aquí
> terminando en :59. Poner 9 alarga la franja una hora entera, que es
> exactamente el error que tenía antes.

> Antes la elegía el cliente: `_tarifaPorDefecto()` en Dart ordenaba por
> `tarifa_base` y se quedaba con la primera, o sea **siempre la más barata**.
> Las tarifas nocturna y de hora pico existían en la tabla pero no se aplicaban
> nunca, y además el cliente podía mandar el id que quisiera.

## La distancia

`cotizar_viaje` acepta un `p_distancia_km` opcional con el recorrido real que
calculó OSRM. **No es un agujero**: el servidor lo acota antes de usarlo.

- Menos que la línea recta → se descarta. Es el mínimo físico entre dos puntos,
  y es justo lo que un pasajero querría falsear para pagar de menos.
- Más de 2,5 veces la línea recta → se descarta.
- Fuera de rango, o sin distancia → se estima como antes: línea recta ×
  `factor_trayecto_urbano()` (1,35).

Comprobado sobre un trayecto de Quito (recta 3,53 km, ruta real 5,92 km):

| Lo que manda el cliente | km que cobra | Total |
|---|---|---|
| nada | 4,77 | 3,56 |
| 5,92 (la ruta real) | 5,92 | 4,31 |
| 0,1 (intento de pagar menos) | 4,77 | 3,56 |
| 60 (intento de inflar) | 4,77 | 3,56 |

Sin esto la tarifa se quedaba un ~19 % corta en ese trayecto, porque cobraba
4,77 km cuando el recorrido real eran 5,92.

## Dónde tocar cada cosa

- **Precios, franjas, mínima y reparto**: filas de la tabla `public.tarifas`.
  No hace falta desplegar la app.
- **Factor de la estimación y velocidad media**:
  `public.factor_trayecto_urbano()` y `public.velocidad_media_kmh()`.
- **Cómo se elige la tarifa**: `public.tarifa_vigente()`.
- **La fórmula**: `public.cotizar_viaje()`.

## Tipos de vehiculo (2026-08-31)

Moto, Estandar, Confort y XL, como en Uber e inDrive.

**La tarifa no se duplica.** Sigue siendo la de `public.tarifas`, con su diurna,
nocturna y hora pico. Cada tipo solo aplica un **factor** sobre ese precio, asi
que cambiar la tarifa de la noche sigue afectando a los cuatro a la vez.

| Tipo | Factor | Pasajeros | Viaje de 4,4 km | Gana el chofer |
|---|---|---|---|---|
| Moto | 0,80 | 1 | 1,16 | 0,99 |
| Estandar | 1,00 | 4 | 1,45 | 1,23 |
| Confort | 1,45 | 4 | 2,10 | 1,79 |
| XL | 1,80 | 6 | 2,61 | 2,22 |

**Subieron el 2026-09-02**, desde 0,65 / 1,00 / 1,30 / 1,55. Estaban
calibrados para unos precios tres veces mayores, y al bajar la tarifa se
quedaron sin nada que multiplicar: en un viaje de 2 km, un chofer de moto se
llevaba **55 centavos**.

El factor multiplica **tambien la carrera minima**. Si solo multiplicara el
bruto, un viaje corto en moto costaria lo mismo que en auto: la minima se lo
comeria. La minima tambien es un precio.

> **Y por eso la minima se subio con los factores.** Con la minima en 1,00, el
> suelo de la moto era 1,00 x 0,65 = **0,65**, y de ahi salian los 55 centavos
> del chofer. Bajar la tarifa sin mirar la minima deja los viajes cortos sin
> suelo, que es donde el chofer ya gana menos. La minima estandar paso de 1,00
> a **1,20**; no toca el viaje de 4,4 km, porque 1,45 sigue por encima.

> **Los factores son una propuesta, no un dato municipal.** La referencia de
> Quito solo tarifa taxis; no dice nada de motos ni de vans. La moto va un 20 %
> por debajo del auto: menos separacion que el 35-45 % de Uber Moto en la
> region, porque con estos precios un descuento mayor deja al chofer sin nada.
> Se cambian con un UPDATE sobre `public.categorias_vehiculo`, sin recompilar
> la app:
>
> ```sql
> update public.categorias_vehiculo set factor = 0.70 where id = 'moto';
> ```

### Como encaja con el resto

- El vehiculo del chofer tiene categoria (`vehiculos.categoria`), y la elige al
  registrarlo.
- El viaje guarda la que se pidio (`viajes.categoria`).
- `aceptar_viaje` **exige que coincidan**: quien conduce una moto no puede tomar
  un viaje que pidio una van. Sin eso, alguien que pide sitio para seis podria
  acabar con una moto en la puerta, y pagando precio de van.
- La lista de solicitudes del chofer filtra ademas en el cliente, para no
  ofrecerle un boton que el servidor va a rechazar.
- `cotizar_categorias` devuelve el precio de los cuatro en **una sola llamada**.
  El selector no los calcula multiplicando por el factor: el redondeo y la
  minima no son lineales y el numero mostrado no cuadraria con el cobrado.

### Los iconos

La base guarda un nombre logico (`moto`, `auto`, `confort`, `van`) y la app lo
traduce a un icono de Material. No se guardan iconos en Postgres: un `IconData`
es un numero de la fuente de iconos de Flutter, y guardarlo ataria la base a una
version concreta del framework.

## Bajada de precios frente a inDrive (2026-09-01, revertida el 2026-09-02)

> **Esto ya no esta vigente.** El 2026-09-02 los precios se revirtieron y ese
> mismo dia se volvieron a ajustar, ahora contra DiDi y Uber (ver «Los
> valores»). Con las tarifas de hoy este trayecto de 8,4 km sale en **2,45**
> frente a los 3,10 que recomendaba inDrive: ahora por debajo. La
> medicion se conserva porque sigue siendo el unico dato que hay de ese
> trayecto concreto.

Medido en Quito, mismo trayecto de 8,4 km hasta la Universidad Central:
inDrive recomendaba **3,10** y Ride cobraba **4,85**.

Lo primero fue entender el 4,85: era la tarifa **nocturna** —eran las 23:00— y
cuadra exacto con `0,65 + 0,50 x 8,4`. De dia el mismo viaje eran 3,78. Es
decir, se estaba comparando nuestra tarifa mas cara contra la recomendada de
ellos. Aun asi, por encima en los dos casos.

Dos cambios:

1. **Baja el precio base.** El km de 0,39 a 0,30 y el arranque de 0,50 a 0,40.
2. **Se suaviza el recargo nocturno**, de +30 % a +18 %. Sigue habiendo recargo
   —conducir de noche vale mas— pero deja de ser lo que duplica el numero que
   ve el pasajero.

| | Arranque | Por km | Por minuto | Minima |
|---|---|---|---|---|
| **Estandar** | 0,40 | 0,30 | 0,08 | 1,25 |
| **Hora pico** (06–09) | 0,44 | 0,33 | 0,09 | 1,38 |
| **Nocturna** (22–05) | 0,47 | 0,35 | 0,09 | 1,48 |

Resultado en ese mismo viaje de 8,4 km:

| | Con 0,50 / 0,39 | Con 0,40 / 0,30 | inDrive |
|---|---|---|---|
| Estandar de dia | 3,78 | **2,92** | 3,10 |
| Estandar de noche | 4,85 | **3,41** | 3,10 |
| Moto de dia | 2,46 | **1,90** | — |

### Lo que cuesta, y hay que vigilarlo

El chofer se lleva el 85 % de la tarifa, asi que cada bajada le llega entera.
Ese viaje de noche le pagaba **4,12** con 0,65/0,50, **2,90** con la bajada de
inDrive y **2,08** con las tarifas de hoy. Es el numero mas bajo por el que ha
pasado el proyecto.

Es el numero a vigilar. El cuello de botella de una app de viajes son los
choferes, no los pasajeros; si dejan de conectarse, la palanca es la tarifa y
no la comision.

El cuello de botella de una app de viajes son los choferes, no los pasajeros.
Si dejan de conectarse, el numero a mover es este —y la palanca es la tarifa,
no la comision: bajar la comision no abarata el viaje, solo cambia quien se
lleva el dinero.

### Sobre comparar con inDrive

Su «tarifa recomendada» **no es un precio fijo**: es la oferta inicial de una
puja. El pasajero puede subirla, y cuando nadie acepta acaba subiendola. El
precio final de un viaje en inDrive suele quedar por encima de lo que muestra
esa pantalla. Conviene tenerlo presente antes de perseguir su numero hasta
donde no salgan las cuentas.
