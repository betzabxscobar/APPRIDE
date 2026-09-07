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
/// Cuando un banco no tiene logo utilizable —hoy, Banco Guayaquil— se dibujan
/// sus iniciales sobre el color de la marca. Es peor que el logo, pero es
/// legible y no deja un hueco.
class BankLogo extends StatelessWidget {
  const BankLogo({super.key, required this.banco, this.alto = 34});

  final Bank banco;

  /// Alto de la placa. El ancho sale de ahí, en proporción 2.6:1, que es más o
  /// menos lo que miden los logos horizontales de los cuatro bancos.
  final double alto;

  /// Los logos que vienen en blanco necesitan el color de la marca detrás; el
  /// resto se leen mejor sobre blanco.
  static const _logosBlancos = {'banco_internacional'};

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final ancho = alto * 2.6;
    final asset = banco.assetLogo;
    final marca = banco.colorMarca;
    final esBlanco = banco.logo != null && _logosBlancos.contains(banco.logo);
    final fondo = esBlanco ? (marca ?? ride.ink) : Colors.white;

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
