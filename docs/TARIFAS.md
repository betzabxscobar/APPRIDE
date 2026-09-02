# Tarifas de Ride

Las calcula Postgres (`public.cotizar_viaje`) y ahí se quedan: el cliente se
puede manipular, así que no puede ser quien diga cuánto cuesta un viaje.

## Los valores

Salen de las tarifas referenciales de taxi de Quito, **con un 10 % menos** por
ser aplicativo:

| | Arranque | Por km | Por minuto | Carrera mínima |
|---|---|---|---|---|
| **Estándar** (resto del día) | 0,50 | 0,39 | 0,10 | 1,44 |
| **Nocturna** (22:00–05:00) | 0,65 | 0,50 | 0,13 | 1,87 |
| **Hora pico** (06:00–09:00) | 0,58 | 0,45 | 0,12 | 1,65 |

Cómo se obtuvieron, partiendo del punto medio de cada rango de referencia:

- arranque diurno 0,50–0,60 → 0,55 × 0,9 = **0,50**
- km diurno 0,40–0,46 → 0,43 × 0,9 = **0,39**
- minuto 0,10–0,12 → 0,11 × 0,9 = **0,10**
- carrera mínima 1,45–1,75 → 1,60 × 0,9 = **1,44**

La nocturna aplica a la diurna la misma subida que la referencia da para el km
de noche (0,56 / 0,43 = 1,30).

> **La hora pico es una suposición.** La referencia municipal no la trae; se
> dejó a medio camino entre diurna y nocturna (+15 % sobre la diurna). Si hay un
> número oficial, cambiarlo en la tabla `tarifas`.

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
cubre, se usa la que no tiene franja.

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

| Tipo | Factor | Pasajeros | Ejemplo (viaje de 6,2 km) |
|---|---|---|---|
| Moto | 0,65 | 1 | 3,56 |
| Estandar | 1,00 | 4 | 5,47 |
| Confort | 1,30 | 4 | 7,11 |
| XL | 1,55 | 6 | 8,48 |

El factor multiplica **tambien la carrera minima**. Si solo multiplicara el
bruto, un viaje corto en moto costaria lo mismo que en auto: la minima se lo
comeria. La minima tambien es un precio.

> **Los factores son una propuesta, no un dato municipal.** La referencia de
> Quito solo tarifa taxis; no dice nada de motos ni de vans. El 0,65 de la moto
> sigue lo que hacen inDrive y Uber Moto en la region, donde va entre un 35 y un
> 45 % por debajo del auto. Se cambian con un UPDATE sobre
> `public.categorias_vehiculo`, sin recompilar la app:
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
