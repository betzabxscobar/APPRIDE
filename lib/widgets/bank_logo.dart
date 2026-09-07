import 'package:flutter/material.dart';

import '../core/ride_colors.dart';
import '../models/fleet.dart';

/// El logo de un banco, en una placa de tamaño fijo.
///
/// Los logos son de marca y vienen como vengan: el de Pichincha es negro, el de
/// Internacional es blanco y el de Produbanco es verde. Ninguno se lleva bien
/// con los dos temas a la vez, así que en vez de pintarlos sobre el fondo de la
/// app van sobre una placa propia —blanca, o del color de la marca cuando el
/// logo es blanco—. Así se ven igual de día y de noche, y de paso todos ocupan
/// lo mismo y la lista queda alineada.
///
/// Cuando un banco no tiene logo utilizable se dibujan sus iniciales sobre el
/// color de la marca. Es peor que el logo, pero es legible y no deja un hueco.
/// Hoy los cuatro bancos tienen el suyo; el respaldo queda para el siguiente
/// que se añada al catálogo antes de conseguir su imagen.
class BankLogo extends StatelessWidget {
  const BankLogo({super.key, required this.banco, this.alto = 34});

  final Bank banco;

  /// Alto de la placa. El ancho sale de ahí, en proporción 2.6:1, que es más o
  /// menos lo que miden los logos horizontales de los cuatro bancos.
  final double alto;

  /// Logos que piden el color de la marca detrás en vez de blanco.
  ///
  /// El de Internacional viene en blanco sobre transparente y sobre blanco no
  /// se vería. El de Guayaquil es un isotipo cuadrado que ya trae su propio
  /// fondo magenta: pintando la placa del mismo color, el recuadro del logo
  /// desaparece y queda una sola placa limpia.
  static const _conColorDeMarca = {'banco_internacional', 'banco_guayaquil'};

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final ancho = alto * 2.6;
    final asset = banco.assetLogo;
    final marca = banco.colorMarca;
    final usaColorDeMarca =
        banco.logo != null && _conColorDeMarca.contains(banco.logo);
    final fondo = usaColorDeMarca ? (marca ?? ride.ink) : Colors.white;

    return Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(
        color: asset == null ? (marca ?? ride.surfaceAlt) : fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ride.border),
      ),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: alto * 0.18, vertical: alto * 0.16),
      child: asset == null
          ? Text(
              banco.iniciales,
              style: TextStyle(
                fontSize: alto * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            )
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              // Un asset que falte no puede tumbar la pantalla de pago: se cae
              // a las iniciales, igual que un banco sin logo.
              errorBuilder: (context, _, _) => Text(
                banco.iniciales,
                style: TextStyle(
                  fontSize: alto * 0.42,
                  fontWeight: FontWeight.w900,
                  color: marca ?? ride.ink,
                ),
              ),
            ),
    );
  }
}
