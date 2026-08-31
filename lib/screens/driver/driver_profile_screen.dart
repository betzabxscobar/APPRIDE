import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';
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
  List<FleetVehicle> _vehiculos = const [];
  List<DriverDocument> _documentos = const [];

  bool _cargando = true;
  String? _error;
  DocumentType? _subiendo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final estado = await RideService.instance.estadoConductor();
      final autos = await FleetService.instance.misVehiculos();
      final docs = await FleetService.instance.misDocumentos();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _vehiculos = autos;
        _documentos = docs;
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

  DriverDocument? _doc(DocumentType tipo) {
    for (final d in _documentos) {
      if (d.tipo == tipo) return d;
    }
    return null;
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

  Future<void> _subir(DocumentType tipo) async {
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

    setState(() {
      _subiendo = tipo;
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

      await FleetService.instance.subirDocumento(tipo, File(foto.path));
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
                  _EstadoCuenta(estado: _estado, documentos: _documentos),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  _Titulo('Mis vehículos', accion: 'Agregar', onTap: _nuevoVehiculo),
                  const SizedBox(height: 10),
                  if (_vehiculos.isEmpty)
                    const _Vacio('Registra tu vehículo para poder recibir viajes.')
                  else
                    for (final auto in _vehiculos) ...[
                      _TarjetaVehiculo(
                        vehiculo: auto,
                        onActivar: () => _activar(auto),
                        onEditar: () => _nuevoVehiculo(editar: auto),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 16),
                  const _Titulo('Mis documentos'),
                  const SizedBox(height: 6),
                  Text(
                    'La administración los revisa antes de aprobar tu cuenta.',
                    style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  for (final tipo in DocumentType.values) ...[
                    _TarjetaDocumento(
                      tipo: tipo,
                      documento: _doc(tipo),
                      subiendo: _subiendo == tipo,
                      onSubir: _subiendo == null ? () => _subir(tipo) : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }
}

class _EstadoCuenta extends StatelessWidget {
  const _EstadoCuenta({required this.estado, required this.documentos});

  final DriverState estado;
  final List<DriverDocument> documentos;

  @override
  Widget build(BuildContext context) {
    final aprobados =
        documentos.where((d) => d.estado == DocumentStatus.aprobado).length;

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
          'Faltan $aprobados de ${DocumentType.values.length} documentos aprobados'
              '${estado.tieneVehiculoActivo ? '' : ' y un vehículo en servicio'}.'
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

    final (color, icono, etiqueta) = switch (doc?.estado) {
      DocumentStatus.aprobado => (context.ride.success, Icons.check_circle, 'Aprobado'),
      DocumentStatus.rechazado =>
        (context.ride.danger, Icons.error_outline, 'Rechazado'),
      DocumentStatus.pendiente =>
        (context.ride.info, Icons.hourglass_empty, 'En revisión'),
      null => (context.ride.inkMuted, Icons.upload_file, 'Sin subir'),
    };

    return RideCard(
      child: Row(
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
