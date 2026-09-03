import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/ride_text_field.dart';
import 'identity_form_sheet.dart';
import 'vehicle_form_sheet.dart';

/// Lo que un chofer necesita para poder trabajar: su vehículo y sus documentos.
///
/// Hasta ahora un conductor solo existía si alguien lo insertaba a mano en la
/// base. Esta pantalla cierra ese hueco.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  DriverState _estado = const DriverState.sinCuenta();
  DriverIdentity _identidad = const DriverIdentity();
  List<FleetVehicle> _vehiculos = const [];
  List<DriverDocument> _documentos = const [];

  /// Lo que le falta, según el servidor. No se calcula aquí: la lista sale de
  /// la misma función que usa `revisar_conductor` para decidir, así que esta
  /// pantalla no puede decir «ya está» sobre algo que va a rebotar.
  List<String> _faltan = const [];

  bool _cargando = true;
  String? _error;

  /// Qué se está subiendo: el tipo y, si es de un auto, cuál.
  (DocumentType, String?)? _subiendo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final estado = await RideService.instance.estadoConductor();
      final identidad = await FleetService.instance.miIdentidad();
      final autos = await FleetService.instance.misVehiculos();
      final docs = await FleetService.instance.misDocumentos();
      // Si todavía no tiene fila en `conductores` esto rebota; no es un error
      // que merezca pantalla, solo significa que no falta nada porque no ha
      // empezado.
      List<String> faltan;
      try {
        faltan = await FleetService.instance.papelesQueFaltan();
      } catch (_) {
        faltan = const [];
      }
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _identidad = identidad;
        _vehiculos = autos;
        _documentos = docs;
        _faltan = faltan;
        _cargando = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus datos.';
        _cargando = false;
      });
    }
  }

  DriverDocument? _doc(DocumentType tipo, {String? vehiculoId}) {
    for (final d in _documentos) {
      if (d.tipo == tipo && d.vehiculoId == vehiculoId) return d;
    }
    return null;
  }

  Future<void> _editarIdentidad() async {
    final guardado =
        await mostrarFormularioIdentidad(context, identidad: _identidad);
    if (guardado == true) await _cargar();
  }

  Future<void> _nuevoVehiculo({FleetVehicle? editar}) async {
    final guardado = await mostrarFormularioVehiculo(context, vehiculo: editar);
    if (guardado == true) await _cargar();
  }

  Future<void> _activar(FleetVehicle auto) async {
    try {
      await FleetService.instance.activarVehiculo(auto.id);
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Pide el número y la fecha de caducidad antes de la foto.
  ///
  /// Se piden aquí y no se leen de la imagen porque nadie lee un PDF ni una
  /// foto por arte de magia, y sin la fecha el papel no cuenta como vigente:
  /// un SPPAT vencido valía igual que uno al día, para siempre.
  Future<(String?, DateTime?)?> _pedirDatosDelPapel(DocumentType tipo) async {
    final numero = TextEditingController();
    DateTime? caduca;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(tipo.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RideTextField(
                label: 'Número',
                hint: tipo == DocumentType.matricula ? 'De la matrícula' : 'De la póliza',
                controller: numero,
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final hoy = DateTime.now();
                  final elegida = await showDatePicker(
                    context: context,
                    initialDate: caduca ?? hoy.add(const Duration(days: 365)),
                    firstDate: hoy.add(const Duration(days: 1)),
                    lastDate: DateTime(hoy.year + 15),
                    helpText: 'Hasta cuándo vale',
                  );
                  if (elegida != null) setLocal(() => caduca = elegida);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: context.ride.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.ride.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined,
                          size: 18, color: context.ride.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          caduca == null
                              ? 'Fecha de caducidad'
                              : _fechaCorta(caduca!),
                          style: TextStyle(
                            fontSize: 13,
                            color: caduca == null
                                ? context.ride.inkMuted
                                : context.ride.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: caduca == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );

    final texto = numero.text.trim();
    numero.dispose();
    if (ok != true) return null;
    return (texto.isEmpty ? null : texto, caduca);
  }

  Future<void> _subir(DocumentType tipo, {FleetVehicle? vehiculo}) async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.ride.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              tipo.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.ride.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tipo.hint,
              style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (origen == null) return;

    String? numero;
    DateTime? caduca;
    if (tipo.caduca) {
      if (!mounted) return;
      final datos = await _pedirDatosDelPapel(tipo);
      if (datos == null) return;
      numero = datos.$1;
      caduca = datos.$2;
    }

    setState(() {
      _subiendo = (tipo, vehiculo?.id);
      _error = null;
    });

    try {
      final picker = ImagePicker();
      // Se reduce antes de subir: una foto de 12 MP pasaría del límite de 5 MB
      // del bucket y no aporta nada para leer una licencia.
      final foto = await picker.pickImage(
        source: origen,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (foto == null) {
        if (mounted) setState(() => _subiendo = null);
        return;
      }

      await FleetService.instance.subirDocumento(
        tipo,
        File(foto.path),
        vehiculoId: vehiculo?.id,
        numero: numero,
        caducaEl: caduca,
      );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tipo.label} enviado a revisión')),
      );
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No pudimos subir el archivo.');
    } finally {
      if (mounted) setState(() => _subiendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta de chofer')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _EstadoCuenta(estado: _estado, faltan: _faltan),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  const _Titulo('Mis datos'),
                  const SizedBox(height: 10),
                  _TarjetaIdentidad(
                    identidad: _identidad,
                    onEditar: _editarIdentidad,
                  ),
                  const SizedBox(height: 22),
                  const _Titulo('Mis documentos'),
                  const SizedBox(height: 6),
                  Text(
                    'La administración los revisa antes de aprobar tu cuenta.',
                    style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  for (final tipo in DocumentType.delChofer) ...[
                    _TarjetaDocumento(
                      tipo: tipo,
                      documento: _doc(tipo),
                      subiendo: _subiendo == (tipo, null),
                      onSubir: _subiendo == null ? () => _subir(tipo) : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 12),
                  _Titulo('Mis vehículos', accion: 'Agregar', onTap: _nuevoVehiculo),
                  const SizedBox(height: 6),
                  Text(
                    'Los papeles son de cada auto: si tienes dos, cada uno '
                    'necesita su matrícula, su SPPAT y su revisión técnica.',
                    style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  if (_vehiculos.isEmpty)
                    const _Vacio('Registra tu vehículo para poder recibir viajes.')
                  else
                    for (final auto in _vehiculos) ...[
                      _TarjetaVehiculo(
                        vehiculo: auto,
                        onActivar: () => _activar(auto),
                        onEditar: () => _nuevoVehiculo(editar: auto),
                      ),
                      // Los papeles, colgando del auto al que pertenecen: en
                      // una lista aparte no se sabría de cuál es cada uno.
                      for (final tipo in DocumentType.delVehiculo)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 8),
                          child: _TarjetaDocumento(
                            tipo: tipo,
                            documento: _doc(tipo, vehiculoId: auto.id),
                            subiendo: _subiendo == (tipo, auto.id),
                            onSubir: _subiendo == null
                                ? () => _subir(tipo, vehiculo: auto)
                                : null,
                          ),
                        ),
                      const SizedBox(height: 18),
                    ],
                ],
              ),
            ),
    );
  }
}

class _EstadoCuenta extends StatelessWidget {
  const _EstadoCuenta({required this.estado, required this.faltan});

  final DriverState estado;

  /// Tal cual lo devuelve `papeles_que_faltan_chofer()`.
  final List<String> faltan;

  @override
  Widget build(BuildContext context) {
    final pendiente = faltan.isEmpty
        ? 'Ya está todo enviado. Falta que la administración lo revise.'
        : 'Te falta: ${faltan.map((f) => etiquetaDePapel(f).toLowerCase()).join('; ')}.';

    final (color, icono, titulo, detalle) = switch (estado.estadoAprobacion) {
      'aprobado' => (
          context.ride.success,
          Icons.verified,
          'Cuenta aprobada',
          'Ya puedes ponerte en línea y recibir viajes.'
        ),
      'rechazado' => (
          context.ride.danger,
          Icons.cancel_outlined,
          'Cuenta rechazada',
          'Revisa tus documentos y vuelve a enviarlos.'
        ),
      _ => (
          context.ride.info,
          Icons.hourglass_top,
          'En revisión',
          pendiente
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 22, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: context.ride.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cédula, dactilar y licencia, o el hueco donde deberían estar.
class _TarjetaIdentidad extends StatelessWidget {
  const _TarjetaIdentidad({required this.identidad, required this.onEditar});

  final DriverIdentity identidad;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final completa = identidad.completa;
    final vencida = completa && identidad.licenciaVencida;

    return RideCard(
      onTap: onEditar,
      child: Row(
        children: [
          Icon(
            completa && !vencida ? Icons.badge : Icons.badge_outlined,
            size: 21,
            color: !completa
                ? ride.inkMuted
                : vencida
                    ? ride.danger
                    : ride.success,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completa ? identidad.cedulaLegible : 'Cédula y licencia',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  !completa
                      ? 'Sin registrar. Toca para completarlos.'
                      : vencida
                          ? 'Licencia ${identidad.licencia!.id} vencida'
                          : 'Licencia ${identidad.licencia!.id} · vence el '
                              '${_fechaCorta(identidad.licenciaCaducaEl!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: vencida ? ride.danger : ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: ride.inkMuted),
        ],
      ),
    );
  }
}

class _TarjetaVehiculo extends StatelessWidget {
  const _TarjetaVehiculo({
    required this.vehiculo,
    required this.onActivar,
    required this.onEditar,
  });

  final FleetVehicle vehiculo;
  final VoidCallback onActivar;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: vehiculo.activo ? context.ride.successSoft : context.ride.background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.directions_car,
              size: 21,
              color: vehiculo.activo ? context.ride.success : context.ride.inkMuted,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        vehiculo.resumen,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.ride.ink,
                        ),
                      ),
                    ),
                    if (vehiculo.activo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.ride.successSoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'En servicio',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: context.ride.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${vehiculo.placa}${vehiculo.color == null ? '' : ' · ${vehiculo.color}'}',
                  style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
                ),
                const SizedBox(height: 6),
                CategoryChip(
                  nombre: _nombreCategoria(vehiculo.categoria),
                  icono: _iconoCategoria(vehiculo.categoria),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) => v == 'activar' ? onActivar() : onEditar(),
            itemBuilder: (context) => [
              if (!vehiculo.activo)
                const PopupMenuItem(
                  value: 'activar',
                  child: Text('Poner en servicio'),
                ),
              const PopupMenuItem(value: 'editar', child: Text('Editar datos')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaDocumento extends StatelessWidget {
  const _TarjetaDocumento({
    required this.tipo,
    required this.documento,
    required this.subiendo,
    required this.onSubir,
  });

  final DocumentType tipo;
  final DriverDocument? documento;
  final bool subiendo;
  final VoidCallback? onSubir;

  @override
  Widget build(BuildContext context) {
    final doc = documento;

    // Un aprobado que ya caducó no es un aprobado: se enseña vencido, porque
    // con él no se puede trabajar.
    final vencido = doc != null && doc.estado == DocumentStatus.aprobado &&
        tipo.caduca && !doc.vigente;

    final (color, icono, etiqueta) = switch (doc?.estado) {
      DocumentStatus.aprobado when vencido =>
        (context.ride.danger, Icons.event_busy, 'Vencido'),
      DocumentStatus.aprobado => (context.ride.success, Icons.check_circle, 'Aprobado'),
      DocumentStatus.rechazado =>
        (context.ride.danger, Icons.error_outline, 'Rechazado'),
      DocumentStatus.pendiente =>
        (context.ride.info, Icons.hourglass_empty, 'En revisión'),
      null => (context.ride.inkMuted, Icons.upload_file, 'Sin subir'),
    };

    final detalle = switch (doc) {
      null => tipo.hint,
      // El motivo manda sobre todo lo demás: es lo único que le dice qué
      // arreglar. Sin esto volvía a subir exactamente el mismo papel.
      _ when doc.estado == DocumentStatus.rechazado && doc.motivoRechazo != null =>
        doc.motivoRechazo!,
      _ when vencido => 'Venció el ${_fechaCorta(doc.caducaEl!)}',
      _ when doc.porCaducar => 'Vence pronto: ${_fechaCorta(doc.caducaEl!)}',
      _ when doc.caducaEl != null => 'Vence el ${_fechaCorta(doc.caducaEl!)}',
      _ => tipo.hint,
    };

    return RideCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 21, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipo.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.ride.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: doc?.estado == DocumentStatus.rechazado
                        ? context.ride.danger
                        : context.ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (subiendo)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            TextButton(
              onPressed: onSubir,
              child: Text(doc == null ? 'Subir' : 'Reemplazar'),
            ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.accion, this.onTap});

  final String texto;
  final String? accion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: context.ride.ink,
            ),
          ),
        ),
        if (accion != null) TextButton(onPressed: onTap, child: Text(accion!)),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.ride.background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: context.ride.border),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
      ),
    );
  }
}

/// Nombre visible de una categoría a partir de su id.
///
/// Se resuelve aquí y no consultando `categorias_vehiculo` porque esta tarjeta
/// ya tiene el id y una consulta más solo para el rótulo no compensa. Si
/// llegara un id desconocido —una categoría nueva— se muestra tal cual, que es
/// mejor que no mostrar nada.
String _nombreCategoria(String id) => switch (id) {
      'moto' => 'Moto',
      'estandar' => 'Estándar',
      'confort' => 'Confort',
      'xl' => 'XL',
      _ => id,
    };

String _iconoCategoria(String id) => switch (id) {
      'moto' => 'moto',
      'confort' => 'confort',
      'xl' => 'van',
      _ => 'auto',
    };

String _fechaCorta(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
