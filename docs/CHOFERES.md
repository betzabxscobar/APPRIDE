# Aprobar a un chofer

Qué se le pide a alguien para poder conducir en Ride, quién lo comprueba y
dónde. Todo lo que decide está en Postgres; la app solo lo enseña.

## Lo que hace falta

**De la persona** — uno por cuenta:

| Qué | Se guarda | Se comprueba |
|---|---|---|
| Cédula | El número, no solo la foto | Dígito verificador, provincia y que sea de persona natural |
| Código dactilar | El del reverso | Formato `V1234I5678` |
| Tipo de licencia | A, A1, B, C, C1, D, D1, E, E1, F o G | Que habilite la categoría del vehículo |
| Caducidad de la licencia | Fecha | Que no haya pasado, cada vez que se conecta |
| Foto de la cédula | Imagen | La aprueba la administración |
| Foto de la licencia | Imagen | La aprueba la administración |
| Foto de la persona | Imagen | La aprueba la administración. Es la misma que ve el pasajero |

**De cada vehículo** — uno por auto, no por chofer:

| Qué | Caduca | Se comprueba |
|---|---|---|
| Matrícula | Sí | Aprobada y vigente |
| SPPAT | Sí | Aprobada y vigente |
| Revisión técnica | Sí | Aprobada y vigente |
| Foto del vehículo | No | Aprobada |

> **SPPAT, no SOAT.** En Ecuador el SOAT lo reemplazó el SPPAT —Servicio
> Público para Pago de Accidentes de Tránsito—. Las filas que existían con
> `SOAT` se renombraron en
> [`2026-09-03-papeles-por-vehiculo.sql`](../infra/sql/2026-09-03-papeles-por-vehiculo.sql).

### Por qué los papeles son del auto

`documentos_conductor` tenía un índice único por `(conductor_id,
tipo_documento)`. Traducido: **un chofer con dos autos tenía una sola
matrícula**, y quien subiera la del segundo pisaba la del primero. Ahora hay dos
índices —uno para los papeles de la persona y otro para los del vehículo— y la
matrícula de cada auto cabe en la tabla.

## Qué licencia habilita qué

| Categoría | Licencias |
|---|---|
| `moto` | A, A1 |
| `estandar` | C |
| `confort` | C |
| `xl` | C, D |

Está en la tabla `licencias_por_categoria`, no en un `case` dentro de una
función, y por la misma razón que las tarifas: esto lo cambia una resolución de
la ANT, no un despliegue.

Con licencia B —la particular— se puede registrar un auto, pero no ponerlo en
servicio: llevar pasajeros por dinero exige licencia profesional. El trigger
`vehiculos_licencia_habilitante` avisa ya al registrarlo, para no descubrirlo
tres pantallas después.

## Dónde se comprueba cada cosa

Aprobar es de una vez; los papeles caducan solos. Por eso se comprueba en tres
momentos distintos, y los tres usan la misma función:

| Cuándo | Qué exige |
|---|---|
| `activar_vehiculo()` | Que la licencia habilite esa categoría y que ese auto tenga sus cuatro papeles aprobados y vigentes |
| `revisar_conductor()` | `papeles_que_faltan_chofer()` vacío: identidad, licencia vigente, sus tres papeles y **al menos un vehículo completo** |
| Ponerse en línea | Lo mismo, otra vez: licencia sin vencer y el vehículo activo con todo al día |

Ese tercer control es el que impide que un chofer aprobado en enero siga
trabajando en abril con el SPPAT vencido en marzo.

`papeles_que_faltan_chofer()` es una sola definición de «está completo». La
pantalla del chofer y la de revisión la llaman en vez de contar documentos por
su cuenta: si cada una tuviera su idea, acabarían enseñando «listo» sobre un
botón que rebota.

## Rechazar con motivo

`revisar_documento()` y `revisar_conductor()` exigen un motivo para rechazar, y
la tabla también (`documentos_rechazo_con_motivo`). Antes se rechazaba y el
chofer no veía por qué, así que volvía a subir exactamente el mismo papel.

Volver a subir un documento lo devuelve a `pendiente` y borra el motivo: es una
revisión nueva, no la anterior con una nota.

## Las fotos

- **Tamaño y tipo** los limita el bucket: 5 MB y `jpeg`, `png`, `webp` o `pdf`.
- **Resolución mínima**: 600 píxeles de lado, comprobado en la app antes de
  subir. Un tope sin suelo deja pasar una foto de 40×30 que nadie puede leer, y
  esa se rechaza igual, solo que tres días más tarde. Postgres no puede
  comprobarlo: no sabe abrir una imagen.
- La foto de perfil que revisa la administración y la que ve el pasajero **son
  la misma**. Tener dos sería pedirle al chofer que suba su cara dos veces y
  dejaría abierta la puerta a que le aprueben una y enseñe otra.

## El agujero que había

Las políticas de `conductores`, `vehiculos` y `documentos_conductor` eran
`for all ... with check (auth.uid() = id)`. Leídas rápido parecen correctas
—«cada quien toca lo suyo»—. Lo que dejaban abierto, comprobado contra la base
real con una sesión de chofer normal:

```sql
update conductores set estado_aprobacion = 'aprobado' where id = <suyo>;
update documentos_conductor set estado = 'aprobado' where conductor_id = <suyo>;
update vehiculos set categoria = 'xl' where conductor_id = <suyo>;
```

Las tres pasaban. Cualquiera con la app instalada podía **saltarse la revisión
entera**, darse por aprobado y cobrar tarifa de camioneta con un auto normal.
No hacía falta ni descompilar el APK: PostgREST acepta el `update` con el token
de sesión.

El fallo no era de las políticas, era de la idea: **RLS decide qué filas ve
alguien, no qué columnas puede escribir.** Para lo segundo están los permisos
por columna:

```sql
revoke insert, update, delete on public.conductores from authenticated;
grant update (disponible) on public.conductores to authenticated;
```

Ponerse en línea y salir de línea es lo único que el chofer decide sobre su
propia fila. Todo lo demás pasa por funciones `security definer`, que corren
como su dueño y no dependen de ese permiso. Y como cerrojo, dos triggers
impiden cambiar `estado_aprobacion` o el estado de un documento a quien no sea
administración, por si algún día alguien vuelve a abrir el permiso.

Está en
[`2026-09-03-cerrar-rls-del-chofer.sql`](../infra/sql/2026-09-03-cerrar-rls-del-chofer.sql).

## Lo que no se comprueba

- **Nada se contrasta con el Registro Civil ni con la ANT.** No hay API pública
  para eso. Lo que sí se hace es que un número inventado o mal copiado no pase:
  la cédula tiene dígito verificador y el dactilar tiene formato fijo. Que la
  cédula sea de quien dice serlo lo decide una persona mirando la foto.
- **Que la foto de la matrícula sea de ese auto** tampoco lo sabe la base. Por
  eso se guarda el número: para poder cotejarlo con la placa.
