import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../models/fare.dart';
import '../../models/vehicle_category.dart';
import '../../services/fare_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// Tarifas y tipos de vehículo, editables desde la app.
///
/// Los precios ya vivían en la base para poder cambiarlos sin publicar una
/// versión nueva, pero hasta ahora había que entrar a Postgres a mano. Esto es
/// esa misma edición, con el cálculo delante para no cambiar un número a
/// ciegas.
///
/// Quien no sea administrativo no llega aquí, y aunque llegara las políticas
/// `tarifas_admin` y `categorias_admin` rechazarían la escritura.
class AdminFaresPanel extends StatefulWidget {
  const AdminFaresPanel({super.key});

  @override
  State<AdminFaresPanel> createState() => _AdminFaresPanelState();
}

class _AdminFaresPanelState extends State<AdminFaresPanel> {
  List<Fare> _tarifas = const [];
  List<VehicleCategory> _categorias = const [];
  bool _cargando = true;
  String? _error;

  /// Distancia con la que se enseña el ejemplo. Un viaje corriente en Quito.
  static const double _kmEjemplo = 5.0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final tarifas = await FareService.instance.tarifas();
      final categorias = await RideService.instance.categorias();
      if (!mounted) return;
      setState(() {
        _tarifas = tarifas;
        _categorias = categorias;
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

  Future<void> _editarTarifa(Fare tarifa) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaTarifa(tarifa: tarifa),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _editarCategoria(VehicleCategory categoria) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaFactor(categoria: categoria),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          Text(
            'TARIFAS POR FRANJA',
            style: TextStyle(
              fontSize: AppText.micro,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: ride.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El servidor elige cuál aplica según la hora. Los ejemplos son '
            'para un viaje de ${_kmEjemplo.toStringAsFixed(0)} km.',
            style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
          ),
          const SizedBox(height: 12),
          for (final t in _tarifas) ...[
            _TarjetaTarifa(
              tarifa: t,
              km: _kmEjemplo,
              onEditar: () => _editarTarifa(t),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
          Text(
            'TIPOS DE VEHÍCULO',
            style: TextStyle(
              fontSize: AppText.micro,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: ride.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cada tipo multiplica la tarifa vigente, carrera mínima incluida.',
            style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
          ),
          const SizedBox(height: 12),
          for (final c in _categorias) ...[
            _TarjetaCategoria(
              categoria: c,
              onEditar: () => _editarCategoria(c),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 20),
          _Advertencia(),
        ],
      ),
    );
  }
}

class _TarjetaTarifa extends StatelessWidget {
  const _TarjetaTarifa({
    required this.tarifa,
    required this.km,
    required this.onEditar,
  });

  final Fare tarifa;
  final double km;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final ejemplo = tarifa.ejemplo(km);

    return RideCard(
      onTap: onEditar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tarifa.nombre,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
              ),
              Text(
                '\$${ejemplo.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: AppText.h3,
                  fontWeight: FontWeight.w900,
                  color: ride.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tarifa.franja,
            style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
          ),
          const Divider(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Dato('Arranque', tarifa.base),
              _Dato('Por km', tarifa.porKm),
              _Dato('Mínima', tarifa.minima),
              _Dato('Al chofer', tarifa.porcentajeConductor, esPorcentaje: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor, {this.esPorcentaje = false});

  final String etiqueta;
  final double valor;
  final bool esPorcentaje;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: ride.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          esPorcentaje
              ? '${(valor * 100).round()} %'
              : '\$${valor.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: AppText.small,
            fontWeight: FontWeight.w800,
            color: ride.ink,
          ),
        ),
      ],
    );
  }
}

class _TarjetaCategoria extends StatelessWidget {
  const _TarjetaCategoria({required this.categoria, required this.onEditar});

  final VehicleCategory categoria;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      onTap: onEditar,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(categoria.icon, size: 26, color: ride.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoria.nombre,
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                Text(
                  categoria.capacidad,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: ride.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '×${(categoria.factor ?? 1).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: AppText.h3,
              fontWeight: FontWeight.w900,
              color: ride.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Advertencia extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ride.infoSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: ride.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 19, color: ride.info),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Un cambio aquí se aplica al instante y a todos los viajes que '
              'se pidan a partir de ese momento. Los ya cerrados conservan su '
              'precio.\n\nBajar la tarifa le quita al chofer: se lleva su '
              'porcentaje de una cifra menor. Bajar la comisión no abarata el '
              'viaje, solo cambia quién se lleva el dinero.',
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.5,
                color: ride.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editar una tarifa.
class _HojaTarifa extends StatefulWidget {
  const _HojaTarifa({required this.tarifa});

  final Fare tarifa;

  @override
  State<_HojaTarifa> createState() => _HojaTarifaState();
}

class _HojaTarifaState extends State<_HojaTarifa> {
  late final _base = TextEditingController(
      text: widget.tarifa.base.toStringAsFixed(2));
  late final _km = TextEditingController(
      text: widget.tarifa.porKm.toStringAsFixed(2));
  late final _minima = TextEditingController(
      text: widget.tarifa.minima.toStringAsFixed(2));
  late final _pct = TextEditingController(
      text: (widget.tarifa.porcentajeConductor * 100).round().toString());

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _base.dispose();
    _km.dispose();
    _minima.dispose();
    _pct.dispose();
    super.dispose();
  }

  double? get _ejemplo {
    final b = double.tryParse(_base.text.replaceAll(',', '.'));
    final k = double.tryParse(_km.text.replaceAll(',', '.'));
    if (b == null || k == null) return null;
    return b + k * 5;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await FareService.instance.guardarTarifa(
        id: widget.tarifa.id,
        base: double.parse(_base.text.replaceAll(',', '.')),
        porKm: double.parse(_km.text.replaceAll(',', '.')),
        minima: double.parse(_minima.text.replaceAll(',', '.')),
        porcentajeConductor:
            double.parse(_pct.text.replaceAll(',', '.')) / 100,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Revisa que los números sean válidos.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final ejemplo = _ejemplo;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tarifa.nombre,
              style: TextStyle(
                fontSize: AppText.h3,
                fontWeight: FontWeight.w800,
                color: ride.ink,
              ),
            ),
            Text(
              widget.tarifa.franja,
              style: TextStyle(fontSize: AppText.micro, color: ride.inkMuted),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _Campo('Arranque', _base, onCambio: _refrescar)),
                const SizedBox(width: 12),
                Expanded(child: _Campo('Por km', _km, onCambio: _refrescar)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Campo('Carrera mínima', _minima)),
                const SizedBox(width: 12),
                Expanded(child: _Campo('% al chofer', _pct)),
              ],
            ),
            if (ejemplo != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ride.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusField),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calculate_outlined, size: 18, color: ride.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Un viaje de 5 km costaría '
                        '\$${ejemplo.toStringAsFixed(2)} en estándar.',
                        style: TextStyle(
                          fontSize: AppText.label,
                          color: ride.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const ButtonSpinner()
                  : const Text('Guardar tarifa'),
            ),
          ],
        ),
      ),
    );
  }

  void _refrescar() => setState(() {});
}

/// Editar el multiplicador de un tipo de vehículo.
class _HojaFactor extends StatefulWidget {
  const _HojaFactor({required this.categoria});

  final VehicleCategory categoria;

  @override
  State<_HojaFactor> createState() => _HojaFactorState();
}

class _HojaFactorState extends State<_HojaFactor> {
  late final _factor = TextEditingController(
      text: (widget.categoria.factor ?? 1).toStringAsFixed(2));

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _factor.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await FareService.instance.guardarFactor(
        id: widget.categoria.id,
        factor: double.parse(_factor.text.replaceAll(',', '.')),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Revisa que el número sea válido.');
    } finally {
      if (mounted) setState(() => _guardando = false);
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
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.categoria.icon, size: 26, color: ride.accent),
              const SizedBox(width: 12),
              Text(
                widget.categoria.nombre,
                style: TextStyle(
                  fontSize: AppText.h3,
                  fontWeight: FontWeight.w800,
                  color: ride.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Campo('Multiplicador', _factor),
          const SizedBox(height: 10),
          Text(
            '1,00 es el precio de la tarifa tal cual. Por debajo abarata —la '
            'moto— y por encima encarece.',
            style: TextStyle(
              fontSize: AppText.micro,
              height: 1.4,
              color: ride.inkMuted,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const ButtonSpinner()
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.etiqueta, this.controlador, {this.onCambio});

  final String etiqueta;
  final TextEditingController controlador;
  final VoidCallback? onCambio;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controlador,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onCambio == null ? null : (_) => onCambio!(),
      style: TextStyle(
        fontSize: AppText.small,
        fontWeight: FontWeight.w700,
        color: context.ride.ink,
      ),
      decoration: InputDecoration(labelText: etiqueta),
    );
  }
}
