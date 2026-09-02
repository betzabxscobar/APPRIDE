import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/support_ticket.dart';
import '../../services/ride_service.dart';
import '../../services/support_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// Soporte, del lado de quien usa la app.
///
/// Sirve igual para pasajeros y para choferes: los dos abren casos y los dos
/// leen la respuesta. Antes no había ninguna vía dentro de la app.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.viajeId});

  /// Si se abre desde un viaje, el caso queda atado a él y la administración
  /// no tiene que preguntar de cuál se trata.
  final String? viajeId;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportTicket> _casos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await SupportService.instance.mios();
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

  Future<void> _nuevo() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _NuevoCaso(viajeId: widget.viajeId),
      ),
    );
    if (creado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soporte')),
      body: _cargando
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
                  FilledButton.icon(
                    onPressed: _nuevo,
                    icon: const Icon(Icons.add_comment_outlined, size: 21),
                    label: const Text('Abrir un caso'),
                  ),
                  const SizedBox(height: 22),
                  if (_casos.isEmpty && _error == null)
                    const _SinCasos()
                  else ...[
                    Text(
                      'TUS CASOS',
                      style: TextStyle(
                        fontSize: AppText.micro,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: context.ride.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final c in _casos) ...[
                      _FilaCaso(caso: c),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _SinCasos extends StatelessWidget {
  const _SinCasos();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.support_agent, size: 46, color: ride.border),
          const SizedBox(height: 16),
          Text(
            'No has abierto ningún caso',
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: FontWeight.w700,
              color: ride.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Si algo salió mal en un viaje, con un cobro o con tu cuenta, '
            'cuéntanoslo y te respondemos por aquí.',
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

/// Un caso con su respuesta, si ya la tiene.
class _FilaCaso extends StatelessWidget {
  const _FilaCaso({required this.caso});

  final SupportTicket caso;

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
          const SizedBox(height: 8),
          Text(
            caso.mensaje,
            style: TextStyle(
              fontSize: AppText.label,
              height: 1.4,
              color: ride.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caso.cuando,
            style: TextStyle(fontSize: AppText.micro, color: ride.inkFaint),
          ),
          if (caso.respondido) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: ride.successSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusField),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.support_agent, size: 15, color: ride.success),
                      const SizedBox(width: 7),
                      Text(
                        'Respuesta de Ride',
                        style: TextStyle(
                          fontSize: AppText.micro,
                          fontWeight: FontWeight.w800,
                          color: ride.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    caso.respuesta!,
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.45,
                      color: ride.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// El estado del caso, con su color.
class EstadoTicketChip extends StatelessWidget {
  const EstadoTicketChip({super.key, required this.estado});

  final TicketStatus estado;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final color = switch (estado) {
      TicketStatus.abierto => ride.info,
      TicketStatus.enProceso => ride.accent,
      TicketStatus.resuelto => ride.success,
      TicketStatus.cerrado => ride.inkMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        estado.label,
        style: TextStyle(
          fontSize: AppText.micro,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// El formulario para abrir un caso.
class _NuevoCaso extends StatefulWidget {
  const _NuevoCaso({this.viajeId});

  final String? viajeId;

  @override
  State<_NuevoCaso> createState() => _NuevoCasoState();
}

class _NuevoCasoState extends State<_NuevoCaso> {
  final _asunto = TextEditingController();
  final _mensaje = TextEditingController();

  TicketCategory _categoria = TicketCategory.otro;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _asunto.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await SupportService.instance.abrir(
        asunto: _asunto.text,
        mensaje: _mensaje.text,
        categoria: _categoria,
        viajeId: widget.viajeId,
      );
      if (!mounted) return;
      final aviso = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      aviso.showSnackBar(
        const SnackBar(content: Text('Caso enviado. Te respondemos pronto.')),
      );
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
      appBar: AppBar(title: const Text('Abrir un caso')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            '¿Sobre qué es?',
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: FontWeight.w800,
              color: ride.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in TicketCategory.values)
                ChoiceChip(
                  avatar: Icon(
                    c.icon,
                    size: 17,
                    color: _categoria == c ? ride.accent : ride.inkMuted,
                  ),
                  label: Text(c.label),
                  selected: _categoria == c,
                  onSelected: _enviando
                      ? null
                      : (_) => setState(() => _categoria = c),
                ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _asunto,
            maxLength: 120,
            enabled: !_enviando,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: AppText.small, color: ride.ink),
            decoration: const InputDecoration(
              labelText: 'Asunto',
              hintText: 'En una línea, qué pasó',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _mensaje,
            maxLength: 2000,
            maxLines: 8,
            minLines: 5,
            enabled: !_enviando,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: AppText.small, color: ride.ink),
            decoration: const InputDecoration(
              labelText: 'Cuéntanos',
              hintText: 'Qué pasó, cuándo y qué esperabas que pasara.',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.viajeId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.link, size: 16, color: ride.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este caso se enviará junto con el viaje desde el que lo '
                    'abriste.',
                    style: TextStyle(
                      fontSize: AppText.micro,
                      color: ride.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enviando ? null : _enviar,
            child: _enviando
                ? const ButtonSpinner()
                : const Text('Enviar caso'),
          ),
        ],
      ),
    );
  }
}
