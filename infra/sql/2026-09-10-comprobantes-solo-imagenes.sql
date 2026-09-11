-- Los comprobantes, solo imagenes
-- ---------------------------------------------------------------------------
-- El chofer ve el comprobante en la app con `Image.network`
-- (driver_trips_screen.dart). Un PDF ahi no se pinta: sale «No pudimos cargar
-- el comprobante», justo cuando tiene que decidir si le pagaron.
--
-- La web dejaba adjuntar un PDF, y ademas lo guardaba como `<viaje>.jpg`. Ya no:
-- convierte la foto a JPEG antes de subirla, y la app nunca dejo elegir un PDF.
-- Esto cierra la puerta a un cliente viejo o hecho a mano.
--
-- El tope de 5 MB se deja como estaba: si la app entrega una captura de
-- pantalla como PNG, puede pasar de 2 MB.
--
-- Mismo cambio en 2026-09-10-pago-por-transferencia.sql, que crea el bucket
-- con `on conflict do update`: si no, volver a ejecutarlo devolvia el PDF.

update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'comprobantes';
