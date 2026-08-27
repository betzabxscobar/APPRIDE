import 'package:flutter/material.dart';

import '../../core/ride_colors.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';

/// Calificación al terminar el viaje. La usan las dos partes.
///
/// Devuelve `true` si se registró. Las reglas las aplica la base: el trigger
/// `validar_calificacion()` exige que el viaje esté finalizado y que quien
/// califica sea uno de sus participantes, y el índice único impide calificar
/// dos veces el mismo viaje.
Future<bool?> mostrarHojaCalificacion(
  BuildContext context, {
  required String viajeId,
  required String calificadoId,
  required String titulo,
  required String subtitulo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    backgroundColor: context.ride.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _HojaCalificacion(
      viajeId: viajeId,
      calificadoId: calificadoId,
      titulo: titulo,
      subtitulo: subtitulo,
    ),
  );
}

class _HojaCalificacion extends StatefulWidget {
  const _HojaCalificacion({
    required this.viajeId,
    required this.calificadoId,
    required this.titulo,
    required this.subtitulo,
  });

  final String viajeId;
  final String calificadoId;
  final String titulo;
  final String subtitulo;

  @override
  State<_HojaCalificacion> createState() => _HojaCalificacionState();
}

class _HojaCalificacionState extends State<_HojaCalificacion> {
  final _comentario = TextEditingController();
  int _puntuacion = 5;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await RideService.instance.calificar(
        viajeId: widget.viajeId,
        calificadoId: widget.calificadoId,
        puntuacion: _puntuacion,
        comentario: _comentario.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: context.ride.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.ride.inkMuted),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: _enviando
                      ? null
                      : () => setState(() => _puntuacion = i),
                  iconSize: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    i <= _puntuacion ? Icons.star : Icons.star_border,
                    color: i <= _puntuacion
                        ? const Color(0xFFF5A623)
                        : context.ride.border,
                  ),
                  tooltip: '$i de 5',
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _comentario,
            enabled: !_enviando,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Cuéntanos algo más (opcional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _enviando ? null : _enviar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(_enviando ? 'Enviando…' : 'Enviar calificación'),
          ),
          TextButton(
            onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
        ],
      ),
    );
  }
}
