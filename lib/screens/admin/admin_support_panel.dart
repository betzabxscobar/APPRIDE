import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/support_ticket.dart';
import '../../services/ride_service.dart';
import '../../services/support_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
import '../support/support_screen.dart' show EstadoTicketChip;

/// La bandeja de soporte de la administración.
///
/// Los casos que llevan más esperando salen primero: es una cola, no un muro.
class AdminSupportPanel extends StatefulWidget {
  const AdminSupportPanel({super.key});

  @override
  State<AdminSupportPanel> createState() => _AdminSupportPanelState();
}

class _AdminSupportPanelState extends State<AdminSupportPanel> {
  TicketStatus? _filtro = TicketStatus.abierto;
  List<SupportTicket> _casos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final lista = await SupportService.instance.todos(estado: _filtro);
      if (!mounted) return;
      setState(() {
        _casos = lista;
        _cargando = false;
        _error = null;
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    }
  }

  Future<void> _responder(SupportTicket caso) async {
    final hecho = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaRespuesta(caso: caso),
    );
    if (hecho == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              for (final (valor, etiqueta) in <(TicketStatus?, String)>[
                (TicketStatus.abierto, 'Abiertos'),
                (TicketStatus.enProceso, 'En proceso'),
                (TicketStatus.resuelto, 'Resueltos'),
                (null, 'Todos'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(etiqueta),
                    selected: _filtro == valor,
                    onSelected: (_) {
                      setState(() => _filtro = valor);
                      _cargar();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],
                      if (_casos.isEmpty && _error == null)
                        _Vacio(filtro: _filtro)
                      else
                        for (final c in _casos) ...[
                          _FilaAdmin(
                            caso: c,
                            onResponder: () => _responder(c),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.filtro});

  final TicketStatus? filtro;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.mark_email_read_outlined, size: 44, color: ride.border),
          const SizedBox(height: 14),
          Text(
            filtro == TicketStatus.abierto
                ? 'No hay casos esperando respuesta.'
                : 'No hay casos con ese estado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _FilaAdmin extends StatelessWidget {
  const _FilaAdmin({required this.caso, required this.onResponder});

  final SupportTicket caso;
  final VoidCallback onResponder;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(caso.categoria.icon, size: 18, color: ride.inkMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  caso.asunto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              EstadoTicketChip(estado: caso.estado),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${caso.autorNombre ?? caso.autorCorreo ?? 'Usuario'} · '
            '${caso.cuando}',
            style: TextStyle(fontSize: AppText.micro, color: ride.inkFaint),
          ),
          const SizedBox(height: 10),
          Text(
            caso.mensaje,
            style: TextStyle(
              fontSize: AppText.label,
              height: 1.45,
              color: ride.inkMuted,
            ),
          ),
          if (caso.respondido) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ride.successSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusField),
              ),
              child: Text(
                caso.respuesta!,
                style: TextStyle(
                  fontSize: AppText.label,
                  height: 1.4,
                  color: ride.ink,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onResponder,
            icon: const Icon(Icons.reply, size: 18),
            label: Text(caso.respondido ? 'Editar respuesta' : 'Responder'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escribir la respuesta y decidir en qué estado queda el caso.
class _HojaRespuesta extends StatefulWidget {
  const _HojaRespuesta({required this.caso});

  final SupportTicket caso;

  @override
  State<_HojaRespuesta> createState() => _HojaRespuestaState();
}

class _HojaRespuestaState extends State<_HojaRespuesta> {
  late final _texto = TextEditingController(text: widget.caso.respuesta ?? '');
  late TicketStatus _estado = widget.caso.estado.esFinal
      ? widget.caso.estado
      : TicketStatus.resuelto;

  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await SupportService.instance.responder(
        ticketId: widget.caso.id,
        respuesta: _texto.text,
        estado: _estado,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        // El teclado tapa el campo si no se le deja sitio.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.caso.asunto,
              style: TextStyle(
                fontSize: AppText.h3,
                fontWeight: FontWeight.w800,
                color: ride.ink,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _texto,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: AppText.small, color: ride.ink),
              decoration: const InputDecoration(
                labelText: 'Respuesta',
                hintText: 'Lo que verá la persona en su pantalla.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dejar el caso como:',
              style: TextStyle(
                fontSize: AppText.label,
                fontWeight: FontWeight.w700,
                color: ride.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in TicketStatus.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _estado == e,
                    onSelected:
                        _enviando ? null : (_) => setState(() => _estado = e),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const ButtonSpinner()
                  : const Text('Enviar respuesta'),
            ),
            const SizedBox(height: 8),
            Text(
              'La persona recibe un aviso con tu respuesta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
