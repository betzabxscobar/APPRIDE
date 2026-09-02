import 'package:flutter/material.dart';

import '../../core/ride_colors.dart';
import '../../models/fleet.dart';
import '../../models/vehicle_category.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_text_field.dart';

/// Alta o edición de un vehículo. Devuelve `true` si se guardó.
Future<bool?> mostrarFormularioVehiculo(
  BuildContext context, {
  FleetVehicle? vehiculo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.ride.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FormularioVehiculo(vehiculo: vehiculo),
  );
}

class _FormularioVehiculo extends StatefulWidget {
  const _FormularioVehiculo({this.vehiculo});

  final FleetVehicle? vehiculo;

  @override
  State<_FormularioVehiculo> createState() => _FormularioVehiculoState();
}

class _FormularioVehiculoState extends State<_FormularioVehiculo> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _placa;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _anio;
  late final TextEditingController _color;

  bool _guardando = false;
  String? _error;

  /// Tipos de vehículo, del catálogo de la base. Vacío mientras cargan.
  List<VehicleCategory> _categorias = const [];
  late String _categoria;

  bool get _esEdicion => widget.vehiculo != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehiculo;
    _placa = TextEditingController(text: v?.placa ?? '');
    _marca = TextEditingController(text: v?.marca ?? '');
    _modelo = TextEditingController(text: v?.modelo ?? '');
    _anio = TextEditingController(text: v?.anio.toString() ?? '');
    _color = TextEditingController(text: v?.color ?? '');
    _categoria = v?.categoria ?? VehicleCategory.idPorDefecto;
    _cargarCategorias();
  }

  /// El catálogo sale de la base, no está escrito aquí: si mañana se añade un
  /// tipo nuevo, aparece solo.
  Future<void> _cargarCategorias() async {
    try {
      final lista = await RideService.instance.categorias();
      if (mounted) setState(() => _categorias = lista);
    } catch (_) {
      // Sin catálogo se guarda con el tipo que ya tenía —o el estándar— y el
      // formulario sigue sirviendo para el resto de los datos.
    }
  }

  @override
  void dispose() {
    _placa.dispose();
    _marca.dispose();
    _modelo.dispose();
    _anio.dispose();
    _color.dispose();
    super.dispose();
  }

  String? _validarAnio(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Indica el año';
    final n = int.tryParse(texto);
    if (n == null) return 'Solo números';
    // El mismo rango que el CHECK de la tabla, para avisar antes de ir al
    // servidor y no mostrar un error de Postgres.
    final maximo = DateTime.now().year + 1;
    if (n < 1950 || n > maximo) return 'Debe estar entre 1950 y $maximo';
    return null;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await FleetService.instance.guardarVehiculo(
        placa: _placa.text,
        marca: _marca.text,
        modelo: _modelo.text,
        anio: int.parse(_anio.text.trim()),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        vehiculoId: widget.vehiculo?.id,
        categoria: _categoria,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _esEdicion ? 'Editar vehículo' : 'Registrar vehículo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.ride.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Estos datos se muestran al pasajero cuando aceptas su viaje.',
                style: TextStyle(fontSize: 12, color: context.ride.inkMuted),
              ),
              const SizedBox(height: 18),
              RideTextField(
                label: 'Placa',
                hint: 'ABC-1234',
                controller: _placa,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 5) return 'Placa incompleta';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: RideTextField(
                      label: 'Marca',
                      hint: 'Chevrolet',
                      controller: _marca,
                      enabled: !_guardando,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RideTextField(
                      label: 'Modelo',
                      hint: 'Sail',
                      controller: _modelo,
                      enabled: !_guardando,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: RideTextField(
                      label: 'Año',
                      hint: '2022',
                      controller: _anio,
                      enabled: !_guardando,
                      keyboardType: TextInputType.number,
                      validator: _validarAnio,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RideTextField(
                      label: 'Color',
                      hint: 'Blanco',
                      controller: _color,
                      enabled: !_guardando,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              if (_categorias.isNotEmpty) ...[
                const SizedBox(height: 18),
                _TipoDeVehiculo(
                  opciones: _categorias,
                  elegida: _categoria,
                  onElegir: _guardando
                      ? null
                      : (id) => setState(() => _categoria = id),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(_guardando ? 'Guardando…' : 'Guardar vehículo'),
              ),
              TextButton(
                onPressed:
                    _guardando ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// De qué tipo es el vehículo: moto, auto, confort o van.
///
/// No es un adorno: decide qué viajes le llegan al chofer y a qué precio se
/// cobran. Un motorizado no ve las solicitudes que pidieron una van, y al
/// revés.
class _TipoDeVehiculo extends StatelessWidget {
  const _TipoDeVehiculo({
    required this.opciones,
    required this.elegida,
    required this.onElegir,
  });

  final List<VehicleCategory> opciones;
  final String elegida;
  final ValueChanged<String>? onElegir;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIPO DE VEHÍCULO',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: ride.inkMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Decide qué viajes puedes tomar.',
          style: TextStyle(fontSize: 11.5, color: ride.inkMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in opciones)
              _Ficha(
                categoria: c,
                seleccionada: c.id == elegida,
                onTap: onElegir == null ? null : () => onElegir!(c.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.categoria,
    required this.seleccionada,
    required this.onTap,
  });

  final VehicleCategory categoria;
  final bool seleccionada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Material(
      color: seleccionada ? ride.accentSoft : ride.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: seleccionada ? ride.accent : ride.border,
              width: seleccionada ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                categoria.icon,
                size: 22,
                color: seleccionada ? ride.accent : ride.inkMuted,
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    categoria.nombre,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ride.ink,
                    ),
                  ),
                  Text(
                    categoria.capacidad,
                    style: TextStyle(fontSize: 10.5, color: ride.inkMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
