import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/fotos.dart';
import 'ride_service.dart' show RideException;

/// Una suscripción recién abierta en PayPal, todavía sin aprobar.
///
/// Tener esto NO significa que el chofer haya pagado: solo que PayPal ya sabe
/// de la suscripción y espera que la apruebe en [aprobarEn].
class PaypalSubscription {
  const PaypalSubscription({required this.id, required this.aprobarEn});

  /// El identificador de PayPal (`I-…`). Sirve para dar soporte.
  final String id;

  /// La página de PayPal donde el chofer aprueba el cobro recurrente.
  final String aprobarEn;
}

/// Los cobros: el viaje del pasajero y la cuota mensual del chofer.
///
/// Ninguno de los dos importes sale de aquí. El del viaje lo pone Postgres al
/// abrir el cobro, leyendo la tarifa; el de la cuota lo pone la Edge Function
/// desde sus variables de entorno. Si el teléfono pudiera decir cuánto cuesta
/// algo, manipular la app abarataría los viajes.
///
/// Y esta clase tampoco da nada por cobrado. Con transferencia solo avisa de
/// que el pasajero dice haber transferido; quien lo confirma es el chofer
/// mirando su banco, porque es el único que puede verlo.
class PaymentsService {
  PaymentsService._();

  static final PaymentsService instance = PaymentsService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Abre la suscripción mensual del chofer y devuelve dónde la aprueba.
  ///
  /// Ni el importe ni el plan viajan desde aquí: los pone la Edge Function
  /// leyendo sus variables de entorno. Y volver del navegador **no** activa
  /// nada — quien da por pagada la cuota es el webhook de PayPal, que es el
  /// único que la base de datos deja escribir.
  Future<PaypalSubscription> abrirSuscripcion() async {
    try {
      final res = await _client.functions.invoke('suscripcion-paypal');
      final datos = res.data;
      if (datos is! Map || datos['aprobar_en'] is! String) {
        throw const RideException('PayPal respondió algo que no entendemos.');
      }
      return PaypalSubscription(
        id: (datos['suscripcion_id'] as String?) ?? '',
        aprobarEn: datos['aprobar_en'] as String,
      );
    } on sb.FunctionException catch (e) {
      throw RideException(_traducirPaypal(e));
    } on RideException {
      rethrow;
    } catch (_) {
      throw const RideException(
        'No pudimos abrir el pago. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  String _traducirPaypal(sb.FunctionException e) {
    final detalles = e.details;
    if (detalles is Map && detalles['error'] is String) {
      return detalles['error'] as String;
    }
    return switch (e.status) {
      401 => 'Debes iniciar sesión para pagar.',
      403 => 'Solo un chofer paga la cuota mensual.',
      404 => 'El cobro con PayPal todavía no está configurado.',
      503 => 'El cobro con PayPal todavía no está configurado.',
      _ => 'No pudimos abrir el pago. Inténtalo de nuevo en un momento.',
    };
  }

  /// El pasajero avisa de que ya transfirió, con el comprobante.
  ///
  /// Esto **no** da el viaje por cobrado: solo se lo dice al chofer, que es el
  /// único que puede ver si el dinero llegó a su cuenta. Él lo confirma con
  /// `confirmar_pago_recibido`, y hasta entonces el viaje no se cierra.
  Future<void> reportarTransferencia(
    String viajeId, {
    String? comprobante,
  }) async {
    try {
      await _client.rpc('reportar_transferencia', params: {
        'p_viaje_id': viajeId,
        'p_comprobante': comprobante,
      });
    } on sb.PostgrestException catch (e) {
      throw RideException(e.message);
    } catch (_) {
      throw const RideException(
        'No pudimos avisar al chofer. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  /// Sube la foto del comprobante y devuelve su ruta dentro del depósito.
  ///
  /// La carpeta es el uuid del pasajero porque la política de acceso lo exige:
  /// cada quien escribe solo en la suya. Lo leen el que lo subió, el chofer de
  /// ese viaje y la administración; nadie más, y el depósito no es público —un
  /// comprobante lleva número de cuenta, nombre y monto—.
  Future<String> subirComprobante(String viajeId, Uint8List bytes) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const RideException('Debes iniciar sesión para subir el comprobante.');
    }
    // Como las demas fotos: a 1600 de ancho, en JPEG y sin metadatos. Antes
    // una captura de pantalla podia llegar como PNG con nombre `.jpg`.
    final Uint8List foto;
    try {
      foto = await prepararFoto(bytes, LimitesFoto.comprobante);
    } on FotoInvalida catch (e) {
      throw RideException(e.message);
    }

    final ruta = '$uid/$viajeId.jpg';
    try {
      await _client.storage.from('comprobantes').uploadBinary(
            ruta,
            foto,
            fileOptions: const sb.FileOptions(
              contentType: 'image/jpeg',
              // Se puede volver a subir: si la primera foto salió movida, la
              // segunda pisa a la primera en vez de acumular basura.
              upsert: true,
            ),
          );
      return ruta;
    } on sb.StorageException catch (e) {
      throw RideException(e.message);
    } catch (_) {
      throw const RideException('No pudimos subir el comprobante.');
    }
  }

  /// Un enlace temporal para mirar el comprobante.
  ///
  /// Firmado y de una hora: el depósito es privado, así que no vale con la URL
  /// pública. Devuelve null si el enlace no se puede crear, y la pantalla
  /// enseña el aviso sin la foto en vez de quedarse en blanco.
  Future<String?> enlaceComprobante(String ruta) async {
    try {
      return await _client.storage
          .from('comprobantes')
          .createSignedUrl(ruta, 3600);
    } catch (_) {
      return null;
    }
  }
}
