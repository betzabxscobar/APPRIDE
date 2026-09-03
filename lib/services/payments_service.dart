import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'ride_service.dart' show RideException;

/// Un cobro con DeUna, tal como lo devuelve la Edge Function `cobro-deuna`.
///
/// El QR llega como *data URI* (`data:image/png;base64,…`) porque así lo manda
/// Payválida, pensando en un `<img>` de una web. Aquí hay que quedarse solo con
/// el base64 para poder pintarlo con [Image.memory].
class DeunaCharge {
  const DeunaCharge({
    required this.orden,
    required this.monto,
    this.qr,
    this.deepLink,
    this.yaPagado = false,
  });

  /// El número de orden que ve Payválida. Sale de `pagos.referencia_externa` y
  /// es el mismo cada vez que se pide el QR de este viaje.
  final String orden;
  final double monto;

  /// La imagen ya decodificada, lista para `Image.memory`.
  final Uint8List? qr;

  /// Enlace que abre la app de DeUna con el cobro cargado. Es la vía cuando se
  /// paga desde el mismo teléfono, donde no hay cómo escanear la propia pantalla.
  final String? deepLink;

  /// El viaje ya estaba cobrado —en efectivo, o porque el pago entró antes—.
  /// No se pide otro QR: sería cobrar dos veces.
  final bool yaPagado;

  factory DeunaCharge.fromMap(Map<String, dynamic> row) => DeunaCharge(
        orden: (row['orden'] as String?) ?? '',
        monto: (row['monto'] as num?)?.toDouble() ?? 0,
        qr: decodificarQr(row['qr'] as String?),
        deepLink: row['deep_link'] as String?,
        yaPagado: row['ya_pagado'] == true,
      );

  /// Saca los bytes del PNG venga con prefijo `data:` o sin él.
  ///
  /// Devuelve null en vez de reventar si el base64 viene roto: quedarse sin QR
  /// es molesto, pero el deeplink todavía sirve para pagar.
  static Uint8List? decodificarQr(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    final coma = valor.indexOf(',');
    final base = valor.startsWith('data:') && coma != -1
        ? valor.substring(coma + 1)
        : valor;
    try {
      return base64Decode(base.trim());
    } catch (_) {
      return null;
    }
  }
}

/// Cobros de un viaje.
///
/// La app no habla nunca con Payválida: pide el cobro a la Edge Function
/// `cobro-deuna`, que es la única que conoce el `fixedhash`. Y el importe no
/// viaja desde aquí —lo pone `cobro_deuna()` leyendo la tabla `pagos`—, así que
/// manipular la app no abarata ningún viaje.
class PaymentsService {
  PaymentsService._();

  static final PaymentsService instance = PaymentsService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  Future<DeunaCharge> cobrarConDeuna(String viajeId) async {
    try {
      final res = await _client.functions.invoke(
        'cobro-deuna',
        body: {'viaje_id': viajeId},
      );
      final datos = res.data;
      if (datos is! Map) {
        throw const RideException('DeUna respondió algo que no entendemos.');
      }
      return DeunaCharge.fromMap(Map<String, dynamic>.from(datos));
    } on sb.FunctionException catch (e) {
      throw RideException(_traducir(e));
    } on RideException {
      rethrow;
    } catch (_) {
      throw const RideException(
        'No pudimos generar el cobro. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  /// Los mensajes de la función ya vienen en español; esto cubre los que no
  /// llegan a ella —que no esté desplegada, o que Payválida no conteste—.
  String _traducir(sb.FunctionException e) {
    final detalles = e.details;
    if (detalles is Map && detalles['error'] is String) {
      return detalles['error'] as String;
    }
    return switch (e.status) {
      401 => 'Debes iniciar sesión para pagar.',
      404 => 'El cobro con DeUna todavía no está configurado.',
      503 => 'El cobro con DeUna todavía no está configurado.',
      _ => 'No pudimos generar el cobro. Inténtalo de nuevo en un momento.',
    };
  }
}
