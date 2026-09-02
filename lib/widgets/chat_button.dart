import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';
import '../models/trip.dart';
import '../screens/trips/chat_screen.dart';
import '../services/chat_service.dart';

/// Abre el chat del viaje, con el número de mensajes sin leer encima.
///
/// La burbuja no es decoración: sin ella nadie se entera de que le escribieron
/// hasta que abre la pantalla, y en un viaje eso llega tarde — el mensaje que
/// importa es «estoy en la esquina, no en el portal».
///
/// Se esconde solo mientras no hay chofer asignado: hasta entonces no hay con
/// quién hablar, y el servidor rechazaría el mensaje.
class ChatButton extends StatefulWidget {
  const ChatButton({
    super.key,
    required this.viaje,
    required this.conQuien,
    this.compacto = false,
  });

  final Trip viaje;

  /// Nombre de la otra persona, para el título del chat.
  final String conQuien;

  /// Solo el icono, para barras donde no cabe una etiqueta.
  final bool compacto;

  @override
  State<ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends State<ChatButton> {
  int _sinLeer = 0;

  @override
  void initState() {
    super.initState();
    _contar();
  }

  @override
  void didUpdateWidget(ChatButton anterior) {
    super.didUpdateWidget(anterior);
    // La pantalla se reconstruye con cada aviso de Realtime; es el momento de
    // volver a contar.
    _contar();
  }

  Future<void> _contar() async {
    if (widget.viaje.conductorId == null) return;
    final n = await ChatService.instance.sinLeer(widget.viaje.id);
    if (mounted && n != _sinLeer) setState(() => _sinLeer = n);
  }

  Future<void> _abrir() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: widget.viaje.id,
          conQuien: widget.conQuien,
        ),
      ),
    );
    await _contar();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viaje.conductorId == null) return const SizedBox.shrink();

    final ride = context.ride;

    final contenido = widget.compacto
        ? Icon(Icons.chat_bubble_outline, size: 21, color: ride.accent)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 19, color: ride.accent),
              const SizedBox(width: 9),
              Text(
                'Mensajes',
                style: TextStyle(
                  fontSize: AppText.small,
                  fontWeight: FontWeight.w700,
                  color: ride.accent,
                ),
              ),
            ],
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: ride.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusField),
          child: InkWell(
            onTap: _abrir,
            borderRadius: BorderRadius.circular(AppTheme.radiusField),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compacto ? 12 : 16,
                vertical: 12,
              ),
              alignment: Alignment.center,
              child: contenido,
            ),
          ),
        ),
        if (_sinLeer > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: ride.danger,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: ride.surface, width: 2),
              ),
              child: Text(
                '$_sinLeer',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
