import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// Métodos de pago del pasajero.
///
/// Solo se ofrece efectivo. La tarjeta existe en el modelo de datos, pero
/// guardarla exige un token de una pasarela de pagos: **esta app nunca pide ni
/// almacena un número de tarjeta**. La función `registrar_metodo_pago` de la
/// base rechaza cualquier valor con forma de PAN, y aquí directamente no hay
/// formulario donde escribirlo.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<PaymentMethod> _metodos = const [];
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final m = await FleetService.instance.misMetodosPago();
      if (!mounted) return;
      setState(() {
        _metodos = m;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus métodos de pago.';
        _cargando = false;
      });
    }
  }

  Future<void> _accion(Future<void> Function() operacion) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await operacion();
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  bool get _tieneEfectivo => _metodos.any((m) => m.esEfectivo);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Métodos de pago')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                if (_metodos.isEmpty)
                  const _Vacio()
                else
                  for (final m in _metodos) ...[
                    _Tarjeta(
                      metodo: m,
                      ocupado: _ocupado,
                      onPredeterminar: m.predeterminado
                          ? null
                          : () => _accion(() => FleetService.instance
                              .elegirPredeterminado(m.id)),
                      onEliminar: () => _confirmarEliminar(m),
                    ),
                    const SizedBox(height: 10),
                  ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 18),
                if (!_tieneEfectivo)
                  FilledButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _accion(() => FleetService.instance
                            .agregarMetodoPago(tipo: 'efectivo')
                            .then((_) {})),
                    icon: const Icon(Icons.payments_outlined, size: 20),
                    label: const Text('Agregar efectivo'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: AppColors.inkMuted),
                      SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'El pago con tarjeta llegará cuando se integre una '
                          'pasarela. Ride nunca guardará el número de tu '
                          'tarjeta: solo un identificador que devuelve la '
                          'pasarela.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmarEliminar(PaymentMethod metodo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar método de pago?'),
        content: Text('Se quitará ${metodo.label.toLowerCase()} de tu cuenta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _accion(() => FleetService.instance.eliminarMetodoPago(metodo.id));
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.metodo,
    required this.ocupado,
    required this.onPredeterminar,
    required this.onEliminar,
  });

  final PaymentMethod metodo;
  final bool ocupado;
  final VoidCallback? onPredeterminar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: metodo.predeterminado
                  ? AppColors.primarySoft
                  : AppColors.background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              metodo.esEfectivo ? Icons.payments_outlined : Icons.credit_card,
              size: 20,
              color: metodo.predeterminado
                  ? AppColors.primary
                  : AppColors.inkMuted,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      metodo.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (metodo.predeterminado) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Principal',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  metodo.descripcion,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: !ocupado,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) =>
                v == 'principal' ? onPredeterminar?.call() : onEliminar(),
            itemBuilder: (context) => [
              if (onPredeterminar != null)
                const PopupMenuItem(
                  value: 'principal',
                  child: Text('Usar como principal'),
                ),
              const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 42, color: AppColors.border),
          const SizedBox(height: 14),
          const Text(
            'Sin métodos de pago',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Agrega uno para que tus viajes queden cobrados al finalizar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
