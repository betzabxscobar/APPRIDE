import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/user_avatar.dart';

/// Revisión de conductores: lo que manda un chofer para que lo aprueben.
///
/// Hasta ahora esto no existía. Un chofer subía su cédula, su licencia, el
/// seguro y la matrícula, la base los guardaba en un bucket privado y ahí se
/// quedaban: **no había ninguna pantalla desde la que verlos**, así que la
/// única forma de aprobar a alguien era entrar a la base a mano.
///
/// Las funciones ya estaban (`revisar_documento`, `revisar_conductor`); lo que
/// faltaba era la pantalla.
class DriverReviewPanel extends StatefulWidget {
  const DriverReviewPanel({super.key});

  @override
  State<DriverReviewPanel> createState() => _DriverReviewPanelState();
}

class _DriverReviewPanelState extends State<DriverReviewPanel> {
  /// Filtro activo. `null` es «todos».
  String? _filtro = 'pendiente';

  List<DriverReview> _conductores = const [];
  bool _cargando = true;
  String? _error;

  static const List<(String?, String)> _filtros = [
    ('pendiente', 'Por revisar'),
    ('aprobado', 'Aprobados'),
    ('rechazado', 'Rechazados'),
    (null, 'Todos'),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista =
          await FleetService.instance.conductoresParaRevision(estado: _filtro);
      if (!mounted) return;
      setState(() {
        _conductores = lista;
        _cargando = false;
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar los conductores.';
        _cargando = false;
      });
    }
  }

  Future<void> _abrir(DriverReview conductor) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverReviewDetailScreen(conductorId: conductor.id),
      ),
    );
    // Al volver, el estado del chofer pudo cambiar: la lista se relee para que
    // no siga apareciendo en «por revisar» alguien que ya se aprobó.
    await _cargar();
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
              for (final (valor, etiqueta) in _filtros)
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
                      if (_conductores.isEmpty && _error == null)
                        _Vacio(filtro: _filtro)
                      else
                        for (final conductor in _conductores) ...[
                          _FilaConductor(
                            conductor: conductor,
                            onTap: () => _abrir(conductor),
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

  final String? filtro;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final texto = switch (filtro) {
      'pendiente' => 'No hay conductores esperando revisión.',
      'aprobado' => 'Todavía no hay ningún conductor aprobado.',
      'rechazado' => 'No hay conductores rechazados.',
      _ => 'No hay conductores registrados.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.how_to_reg_outlined, size: 44, color: ride.border),
          const SizedBox(height: 14),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.small, color: ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Una fila de la lista: quién es, cómo va y qué le falta.
class _FilaConductor extends StatelessWidget {
  const _FilaConductor({required this.conductor, required this.onTap});

  final DriverReview conductor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final auto = conductor.vehiculoActivo;

    return RideCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          UserAvatar(
            iniciales: conductor.iniciales,
            fotoUrl: conductor.fotoUrl,
            radio: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conductor.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  auto == null
                      ? 'Sin vehículo registrado'
                      : '${auto.resumen} · ${auto.placa}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _EstadoChip(estado: conductor.estadoAprobacion),
                    const SizedBox(width: 8),
                    Text(
                      conductor.papelesQueFaltan.isEmpty
                          ? 'Todo en regla'
                          : 'Le faltan ${conductor.papelesQueFaltan.length}',
                      style: TextStyle(
                        fontSize: AppText.micro,
                        fontWeight: FontWeight.w700,
                        color: conductor.faltantes.isEmpty
                            ? ride.success
                            : ride.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 22, color: ride.inkFaint),
        ],
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final (color, texto) = switch (estado) {
      'aprobado' => (ride.success, 'Aprobado'),
      'rechazado' => (ride.danger, 'Rechazado'),
      _ => (ride.info, 'Por revisar'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: AppText.micro,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// La ficha completa de un chofer, con sus papeles y los botones de decisión.
class DriverReviewDetailScreen extends StatefulWidget {
  const DriverReviewDetailScreen({super.key, required this.conductorId});

  final String conductorId;

  @override
  State<DriverReviewDetailScreen> createState() =>
      _DriverReviewDetailScreenState();
}

class _DriverReviewDetailScreenState extends State<DriverReviewDetailScreen> {
  DriverReview? _conductor;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final conductor =
          await FleetService.instance.conductorParaRevision(widget.conductorId);
      if (!mounted) return;
      setState(() {
        _conductor = conductor;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar la ficha.';
        _cargando = false;
      });
    }
  }

  Future<void> _accion(Future<void> Function() operacion, String exito) async {
    setState(() {
      _ocupado = true;
      _error = null;
      _aviso = null;
    });
    try {
      await operacion();
      await _cargar();
      if (mounted) setState(() => _aviso = exito);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo completar la acción.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _revisarDocumento(DriverDocument doc, bool aprobado) async {
    String? motivo;
    if (!aprobado) {
      motivo = await _pedirMotivo(
        titulo: '¿Por qué se rechaza ${doc.tipo.label.toLowerCase()}?',
        ayuda: 'El chofer solo va a leer esto. «Ilegible» o «vencida» le dice '
            'qué arreglar; sin motivo vuelve a subir lo mismo.',
      );
      if (motivo == null) return;
    }

    return _accion(
      () => FleetService.instance
          .revisarDocumento(doc.id, aprobado, motivo: motivo),
      aprobado
          ? '${doc.tipo.label}: aprobado'
          : '${doc.tipo.label}: rechazado',
    );
  }

  /// Pide el motivo del rechazo. Devuelve null si se cancela.
  ///
  /// La base lo exige —`revisar_documento` rebota sin motivo—, así que esto no
  /// es la validación: es no llegar hasta allí para que rebote.
  Future<String?> _pedirMotivo({
    required String titulo,
    required String ayuda,
  }) async {
    final texto = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ayuda,
                style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: texto,
                autofocus: true,
                maxLines: 3,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'La foto está borrosa y no se lee el número',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: texto.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: context.ride.danger,
              ),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      ),
    );

    final motivo = texto.text.trim();
    texto.dispose();
    return ok == true && motivo.isNotEmpty ? motivo : null;
  }

  Future<void> _revisarCuenta(bool aprobado) async {
    String? motivo;
    if (!aprobado) {
      motivo = await _pedirMotivo(
        titulo: '¿Por qué se rechaza la cuenta?',
        ayuda: 'No podrá ponerse en línea ni recibir viajes. Se le avisa del '
            'rechazo con este motivo y podrá volver a enviar sus documentos.',
      );
      if (motivo == null) return;
    }

    await _accion(
      () => FleetService.instance
          .revisarConductor(widget.conductorId, aprobado, motivo: motivo)
          .then((_) {}),
      aprobado ? 'Conductor aprobado' : 'Conductor rechazado',
    );
  }

  @override
  Widget build(BuildContext context) {
    final conductor = _conductor;

    return Scaffold(
      appBar: AppBar(title: const Text('Ficha del conductor')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : conductor == null
              ? const Center(child: Text('No encontramos a este conductor.'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      _Identidad(conductor: conductor),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        ErrorBanner(message: _error!),
                      ],
                      if (_aviso != null) ...[
                        const SizedBox(height: 14),
                        NoticeBanner(message: _aviso!),
                      ],
                      const SizedBox(height: 24),
                      const _Encabezado('Vehículos'),
                      const SizedBox(height: 10),
                      if (conductor.vehiculos.isEmpty)
                        const _SinDatos(
                          'No registró ningún vehículo. Sin auto no se puede '
                          'aprobar la cuenta.',
                        )
                      else
                        for (final auto in conductor.vehiculos) ...[
                          _TarjetaAuto(auto: auto),
                          // Los papeles de ese auto, debajo de ese auto. En una
                          // lista suelta no se sabe de cuál es cada matrícula,
                          // y con dos vehículos eso es justo lo que hay que
                          // poder distinguir.
                          for (final tipo in DocumentType.delVehiculo)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 8),
                              child: _TarjetaDocumento(
                                tipo: tipo,
                                documento: conductor
                                    .documentosDe(auto.id)
                                    .where((d) => d.tipo == tipo)
                                    .firstOrNull,
                                ocupado: _ocupado,
                                onAprobar: (doc) => _revisarDocumento(doc, true),
                                onRechazar: (doc) => _revisarDocumento(doc, false),
                              ),
                            ),
                          const SizedBox(height: 18),
                        ],
                      const SizedBox(height: 18),
                      const _Encabezado('Documentos de la persona'),
                      const SizedBox(height: 10),
                      for (final tipo in DocumentType.delChofer) ...[
                        _TarjetaDocumento(
                          tipo: tipo,
                          documento: conductor.documento(tipo),
                          ocupado: _ocupado,
                          onAprobar: (doc) => _revisarDocumento(doc, true),
                          onRechazar: (doc) => _revisarDocumento(doc, false),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 22),
                      _Decision(
                        conductor: conductor,
                        ocupado: _ocupado,
                        onAprobar: () => _revisarCuenta(true),
                        onRechazar: () => _revisarCuenta(false),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Quién es y cómo contactarlo.
class _Identidad extends StatelessWidget {
  const _Identidad({required this.conductor});

  final DriverReview conductor;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                iniciales: conductor.iniciales,
                fotoUrl: conductor.fotoUrl,
                radio: 30,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conductor.nombre,
                      style: TextStyle(
                        fontSize: AppText.h3,
                        fontWeight: FontWeight.w800,
                        color: ride.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _EstadoChip(estado: conductor.estadoAprobacion),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          _Dato(
            icono: Icons.alternate_email,
            etiqueta: 'Correo',
            valor: conductor.email,
          ),
          const SizedBox(height: 12),
          _Dato(
            icono: Icons.phone_outlined,
            etiqueta: 'Número celular',
            valor: conductor.telefono ?? 'Sin registrar',
            alerta: conductor.telefono == null,
          ),
          const SizedBox(height: 12),
          // Los tres datos que hay que cotejar con las fotos que subió. Antes
          // no existían: de la identidad de un chofer solo había imágenes, y
          // aprobar era mirar una foto y creerse lo que decía.
          _Dato(
            icono: Icons.badge_outlined,
            etiqueta: 'Cédula',
            valor: conductor.cedula ?? 'Sin registrar',
            alerta: conductor.cedula == null,
          ),
          const SizedBox(height: 12),
          _Dato(
            icono: Icons.fingerprint,
            etiqueta: 'Código dactilar',
            valor: conductor.codigoDactilar ?? 'Sin registrar',
            alerta: conductor.codigoDactilar == null,
          ),
          const SizedBox(height: 12),
          _Dato(
            icono: Icons.credit_card_outlined,
            etiqueta: 'Licencia',
            valor: conductor.licencia == null
                ? 'Sin registrar'
                : conductor.licenciaVencida
                    ? '${conductor.licencia!.label} · VENCIDA'
                    : '${conductor.licencia!.label} · vence el '
                        '${_fecha(conductor.licenciaCaducaEl!)}',
            alerta: conductor.licencia == null || conductor.licenciaVencida,
          ),
          const SizedBox(height: 12),
          _Dato(
            icono: Icons.star_outline,
            etiqueta: 'Calificación',
            valor: conductor.calificacion == null
                ? 'Todavía sin viajes calificados'
                : conductor.calificacion!.toStringAsFixed(1),
          ),
          const SizedBox(height: 12),
          _Dato(
            icono: Icons.event_outlined,
            etiqueta: 'Se registró',
            valor: conductor.fechaRegistro == null
                ? 'Sin fecha'
                : _fecha(conductor.fechaRegistro!),
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/${f.year}';
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.alerta = false,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Row(
      children: [
        Icon(icono, size: 18, color: alerta ? ride.danger : ride.inkMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: ride.inkFaint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: TextStyle(
                  fontSize: AppText.small,
                  fontWeight: FontWeight.w700,
                  color: alerta ? ride.danger : ride.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaAuto extends StatelessWidget {
  const _TarjetaAuto({required this.auto});

  final FleetVehicle auto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.directions_car,
            size: 24,
            color: auto.activo ? ride.success : ride.inkMuted,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auto.resumen,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  auto.color == null
                      ? (auto.activo ? 'En servicio' : 'Registrado')
                      : '${auto.color}'
                          '${auto.activo ? ' · En servicio' : ''}',
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          // La placa se lee como una placa: en caja, en mayúsculas y con aire
          // entre letras. Es el dato que más se contrasta contra el papel.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: ride.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ride.border),
            ),
            child: Text(
              auto.placa,
              style: TextStyle(
                fontSize: AppText.label,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: ride.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un documento: su estado, el archivo y las dos decisiones posibles.
class _TarjetaDocumento extends StatelessWidget {
  const _TarjetaDocumento({
    required this.tipo,
    required this.documento,
    required this.ocupado,
    required this.onAprobar,
    required this.onRechazar,
  });

  final DocumentType tipo;
  final DriverDocument? documento;
  final bool ocupado;
  final ValueChanged<DriverDocument> onAprobar;
  final ValueChanged<DriverDocument> onRechazar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final doc = documento;

    final (color, etiqueta) = switch (doc?.estado) {
      DocumentStatus.aprobado => (ride.success, 'Aprobado'),
      DocumentStatus.rechazado => (ride.danger, 'Rechazado'),
      DocumentStatus.pendiente => (ride.info, 'Por revisar'),
      null => (ride.inkFaint, 'No lo ha subido'),
    };

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(tipo.icon, size: 21, color: color),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipo.label,
                      style: TextStyle(
                        fontSize: AppText.small,
                        fontWeight: FontWeight.w800,
                        color: ride.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doc == null
                          ? etiqueta
                          : '$etiqueta · ${_cuando(doc.fechaSubida)}',
                      style: TextStyle(
                        fontSize: AppText.micro,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (doc != null) ...[
            const SizedBox(height: 14),
            _VistaDocumento(documento: doc),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ocupado || doc.estado == DocumentStatus.rechazado
                        ? null
                        : () => onRechazar(doc),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: ride.danger,
                      side: BorderSide(
                        color: ride.danger.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: ocupado || doc.estado == DocumentStatus.aprobado
                        ? null
                        : () => onAprobar(doc),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: ride.success,
                    ),
                    child: const Text('Aprobar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _cuando(DateTime f) {
    final d = DateTime.now().difference(f);
    if (d.inMinutes < 60) return 'subido hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'subido hace ${d.inHours} h';
    if (d.inDays == 1) return 'subido ayer';
    return 'subido hace ${d.inDays} días';
  }
}

/// El archivo del documento.
///
/// El bucket `documentos` es privado, así que no hay una URL fija que pegar en
/// un `Image.network`: hay que pedir una firmada cada vez. Dura una hora y es
/// lo que impide que un enlace filtrado deje la cédula de alguien colgada en
/// internet para siempre.
class _VistaDocumento extends StatefulWidget {
  const _VistaDocumento({required this.documento});

  final DriverDocument documento;

  @override
  State<_VistaDocumento> createState() => _VistaDocumentoState();
}

class _VistaDocumentoState extends State<_VistaDocumento> {
  String? _url;
  bool _fallo = false;

  bool get _esPdf => widget.documento.url.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _firmar();
  }

  @override
  void didUpdateWidget(_VistaDocumento anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.documento.url != widget.documento.url) _firmar();
  }

  Future<void> _firmar() async {
    if (_esPdf) return;
    try {
      final url =
          await FleetService.instance.urlDocumento(widget.documento.url);
      if (mounted) setState(() => _url = url);
    } catch (_) {
      if (mounted) setState(() => _fallo = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    // Un PDF no se puede pintar aquí sin arrastrar un visor entero. Se dice
    // claramente en vez de enseñar un recuadro roto.
    if (_esPdf) {
      return _Marco(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_outlined, size: 34, color: ride.inkMuted),
              const SizedBox(height: 8),
              Text(
                'Documento en PDF',
                style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_fallo) {
      return _Marco(
        child: Center(
          child: Text(
            'No pudimos abrir el archivo',
            style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
          ),
        ),
      );
    }

    final url = _url;
    if (url == null) {
      return const _Marco(child: Center(child: CircularProgressIndicator()));
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DocumentoPantallaCompleta(
            url: url,
            titulo: widget.documento.tipo.label,
          ),
        ),
      ),
      child: _Marco(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              'No pudimos mostrar la imagen',
              style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _Marco extends StatelessWidget {
  const _Marco({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusField),
      child: Container(
        height: 168,
        width: double.infinity,
        color: ride.surfaceAlt,
        child: child,
      ),
    );
  }
}

/// El documento en grande, con zoom.
///
/// Leer un número de cédula en un recuadro de 168 px no es realista, y de eso
/// depende que la aprobación signifique algo.
class _DocumentoPantallaCompleta extends StatelessWidget {
  const _DocumentoPantallaCompleta({required this.url, required this.titulo});

  final String url;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: Image.network(url)),
      ),
    );
  }
}

/// Aprobar o rechazar la cuenta entera.
class _Decision extends StatelessWidget {
  const _Decision({
    required this.conductor,
    required this.ocupado,
    required this.onAprobar,
    required this.onRechazar,
  });

  final DriverReview conductor;
  final bool ocupado;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final puede = conductor.listoParaAprobar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!puede)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: ride.infoSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusField),
              border: Border.all(color: ride.info.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 19, color: ride.info),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    _queFalta(conductor),
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: ride.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          // Aprobar con algo pendiente lo rechaza el servidor de todos modos;
          // el botón se apaga para no ofrecer algo que va a fallar.
          onPressed: ocupado || !puede || conductor.aprobado ? null : onAprobar,
          icon: const Icon(Icons.verified_outlined, size: 21),
          label: Text(
            conductor.aprobado ? 'Cuenta ya aprobada' : 'Aprobar conductor',
          ),
          style: FilledButton.styleFrom(backgroundColor: ride.success),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: ocupado || conductor.rechazado ? null : onRechazar,
          icon: Icon(Icons.block, size: 20, color: ride.danger),
          label: Text(
            conductor.rechazado ? 'Cuenta ya rechazada' : 'Rechazar conductor',
            style: TextStyle(color: ride.danger),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: ride.danger.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  /// La lista la arma `papeles_que_faltan_chofer()`, la misma función que usa
  /// `revisar_conductor` para decidir. Antes esta pantalla la calculaba por su
  /// cuenta, que es como se acaba enseñando «listo» sobre un botón que rebota.
  static String _queFalta(DriverReview conductor) {
    final partes = conductor.faltantes.map((f) => f.toLowerCase()).join('; ');
    return 'Todavía no se puede aprobar — falta $partes.';
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: AppText.micro,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: context.ride.inkMuted,
      ),
    );
  }
}

class _SinDatos extends StatelessWidget {
  const _SinDatos(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ride.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: ride.border),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: AppText.label,
          height: 1.45,
          color: ride.inkMuted,
        ),
      ),
    );
  }
}
