import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../services/payments_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// El QR con el que el pasajero paga su viaje por DeUna.
///
/// Dos caminos, porque el pasajero puede estar en dos situaciones distintas:
/// escanear el QR desde otro teléfono, o —lo normal— abrir DeUna en el mismo
/// aparato, donde no hay forma de escanear la propia pantalla.
///
/// El importe no se escribe aquí ni se manda: lo pone la base al abrir el
/// cobro. Esta pantalla solo enseña lo que la pasarela devolvió.
class DeunaQrScreen extends StatefulWidget {
  const DeunaQrScreen({super.key, required this.viajeId});

  final String viajeId;

  static Future<void> abrir(BuildContext context, {required String viajeId}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeunaQrScreen(viajeId: viajeId)),
    );
  }

  @override
  State<DeunaQrScreen> createState() => _DeunaQrScreenState();
}

class _DeunaQrScreenState extends State<DeunaQrScreen> {
  DeunaCharge? _cobro;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pedir();
  }

  Future<void> _pedir() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final cobro = await PaymentsService.instance.cobrarConDeuna(widget.viajeId);
      if (!mounted) return;
      setState(() {
        _cobro = cobro;
        _cargando = false;
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    }
  }

  Future<void> _abrirDeuna() async {
    final enlace = _cobro?.deepLink;
    if (enlace == null) return;
    final url = Uri.parse(enlace);
    // `externalApplication`: el pago tiene que ocurrir en la app de DeUna, no
    // dentro de una vista web de Ride.
    final abrio = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!abrio && mounted) {
      setState(() => _error = 'No pudimos abrir la app de DeUna en este teléfono.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cobro = _cobro;

    return Scaffold(
      appBar: AppBar(title: const Text('Pagar con DeUna')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _pedir,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Reintentar'),
                  ),
                ] else if (cobro != null && cobro.yaPagado)
                  const _YaPagado()
                else if (cobro != null) ...[
                  _Importe(monto: cobro.monto),
                  const SizedBox(height: 16),
                  _Qr(cobro: cobro),
                  const SizedBox(height: 16),
                  if (cobro.deepLink != null)
                    FilledButton.icon(
                      onPressed: _abrirDeuna,
                      icon: const Icon(Icons.open_in_new, size: 19),
                      label: const Text('Abrir la app de DeUna'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const _Aviso(),
                ],
              ],
            ),
    );
  }
}

class _Importe extends StatelessWidget {
  const _Importe({required this.monto});

  final double monto;

  @override
  Widget build(BuildContext context) {
    return RideCard(
      child: Row(
        children: [
          Icon(Icons.payments_outlined, size: 20, color: context.ride.inkMuted),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              'Total del viaje',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.ride.ink,
              ),
            ),
          ),
          Text(
            '\$${monto.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: context.ride.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr({required this.cobro});

  final DeunaCharge cobro;

  @override
  Widget build(BuildContext context) {
    final qr = cobro.qr;

    return RideCard(
      child: Column(
        children: [
          if (qr != null)
            // Fondo blanco fijo, también en modo oscuro: un QR sobre un fondo
            // oscuro no lo lee ningún teléfono.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Image.memory(qr, width: 220, height: 220),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'DeUna no devolvió el código. Usa el botón de abajo para pagar '
                'desde la app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Orden ${cobro.orden}',
            style: TextStyle(fontSize: 11, color: context.ride.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.ride.background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: context.ride.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: context.ride.inkMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'El viaje queda como pagado cuando DeUna nos confirme el cobro. '
              'Si acabas de pagar y sigue pendiente, dale unos minutos.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: context.ride.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YaPagado extends StatelessWidget {
  const _YaPagado();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 42, color: context.ride.accent),
          const SizedBox(height: 14),
          Text(
            'Este viaje ya está pagado',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.ride.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'No hace falta que pagues otra vez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: context.ride.inkMuted),
          ),
        ],
      ),
    );
  }
}
