import 'package:flutter/material.dart';

import '../core/ride_colors.dart';

/// La foto de alguien, o sus iniciales mientras no tenga una.
///
/// Existe para que las iniciales y la foto no se pinten de dos formas
/// distintas según la pantalla. Antes solo había iniciales, repetidas a mano
/// en la hoja de cuenta, en las dos barras del mapa y en el panel
/// administrativo.
///
/// Si la imagen no carga —sin red, o una URL que ya no existe— cae a las
/// iniciales sin dejar el hueco roto de siempre.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.iniciales,
    this.fotoUrl,
    this.radio = 24,
    this.color,
    this.fondo,
  });

  final String iniciales;
  final String? fotoUrl;
  final double radio;

  /// Color del texto de las iniciales. Por defecto, el azul del tema.
  final Color? color;

  /// Fondo tras las iniciales.
  final Color? fondo;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final tinta = color ?? ride.accent;
    final url = fotoUrl;

    final texto = Text(
      iniciales,
      style: TextStyle(
        // Las iniciales ocupan poco más de un tercio del círculo: por encima
        // de eso rozan el borde en los avatares grandes.
        fontSize: radio * 0.72,
        fontWeight: FontWeight.w800,
        color: tinta,
      ),
    );

    return CircleAvatar(
      radius: radio,
      backgroundColor: fondo ?? tinta.withValues(alpha: ride.isDark ? 0.22 : 0.14),
      child: url == null || url.isEmpty
          ? texto
          : ClipOval(
              child: Image.network(
                url,
                width: radio * 2,
                height: radio * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => texto,
                loadingBuilder: (context, hijo, progreso) =>
                    progreso == null ? hijo : texto,
              ),
            ),
    );
  }
}
