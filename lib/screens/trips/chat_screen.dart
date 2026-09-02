import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../services/chat_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';

/// El chat de un viaje, entre el pasajero y su chofer.
///
/// Se abre desde el viaje y solo existe mientras el viaje existe. No es una
/// mensajería: es para «estoy en la puerta de atrás» o «me dejé la mochila».
///
/// Quién puede escribir lo decide Postgres. Aquí, si el servidor dice que no,
/// se enseña el motivo y se bloquea el campo — pero la barrera está allí, no
/// en esta pantalla.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.viajeId,
    required this.conQuien,
  });

  final String viajeId;

  /// Nombre de la otra persona, para el título.
  final String conQuien;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();

  sb.RealtimeChannel? _canal;
  List<ChatMessage> _mensajes = const [];
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    _canal = ChatService.instance.escuchar(widget.viajeId, _cargar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) ChatService.instance.cerrarCanal(canal);
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final lista = await ChatService.instance.mensajes(widget.viajeId);
      if (!mounted) return;
      setState(() {
        _mensajes = lista;
        _cargando = false;
      });

      // Se marcan leídos al verlos, que es cuando de verdad se leyeron.
      await ChatService.instance.marcarLeidos(widget.viajeId);
      _alFinal();
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    }
  }

  /// Baja al último mensaje. Tras el frame: antes de pintarlo, el `ListView`
  /// todavía no sabe cuánto mide y `maxScrollExtent` sale mal.
  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ChatService.instance.enviar(widget.viajeId, texto);
      _texto.clear();
      await _cargar();
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Scaffold(
      appBar: AppBar(title: Text(widget.conQuien)),
      body: Column(
        children: [
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _mensajes.isEmpty
                    ? const _Vacio()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _mensajes.length,
                        itemBuilder: (context, i) =>
                            _Burbuja(mensaje: _mensajes[i]),
                      ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ErrorBanner(message: _error!),
            ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: ride.surface,
                border: Border(top: BorderSide(color: ride.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _texto,
                      // El mismo tope que acepta la base. Sin él, el mensaje se
                      // rechazaría al enviarlo y nadie sabría por qué.
                      maxLength: 500,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: AppText.small,
                        color: ride.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: ride.accent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _enviando ? null : _enviar,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _enviando
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: 21,
                                color: ride.isDark
                                    ? const Color(0xFF04121C)
                                    : Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 44, color: ride.border),
          const SizedBox(height: 16),
          Text(
            'Aún no hay mensajes',
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: FontWeight.w700,
              color: ride.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Úsalo para lo justo: dónde estás exactamente, si te retrasas o si '
            'te dejaste algo en el auto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.micro,
              height: 1.45,
              color: ride.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje});

  final ChatMessage mensaje;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final mio = mensaje.esMio;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            mio ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: mio ? ride.accent : ride.surfaceAlt,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  // La esquina de tu lado se recorta: es lo que hace que se lea
                  // de un vistazo quién dijo qué, sin leer nada.
                  bottomLeft: Radius.circular(mio ? 16 : 4),
                  bottomRight: Radius.circular(mio ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    mensaje.texto,
                    style: TextStyle(
                      fontSize: AppText.small,
                      height: 1.35,
                      color: mio
                          ? (ride.isDark
                              ? const Color(0xFF04121C)
                              : Colors.white)
                          : ride.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mensaje.hora,
                        style: TextStyle(
                          fontSize: 10,
                          color: mio
                              ? (ride.isDark
                                  ? const Color(0x9904121C)
                                  : Colors.white70)
                              : ride.inkFaint,
                        ),
                      ),
                      if (mio) ...[
                        const SizedBox(width: 4),
                        Icon(
                          mensaje.leido ? Icons.done_all : Icons.done,
                          size: 13,
                          color: ride.isDark
                              ? const Color(0x9904121C)
                              : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
