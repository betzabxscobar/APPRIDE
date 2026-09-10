import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../services/payments_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_card.dart';

/// La cuota mensual del chofer: 15 USD para poder recibir viajes.
///
/// Lo que se ve aquí es un espejo de lo que dice Postgres, no la verdad. El
/// corte de verdad está en `aceptar_viaje()`: aunque alguien parchee el APK
/// para que esta pantalla diga «al día», el servidor le sigue rebotando los
/// viajes. Ver infra/sql/2026-09-09-suscripcion-del-chofer.sql.
///
/// El pago se abre en el navegador con la suscripción ya creada a nombre del
/// chofer. **Volver de PayPal no activa nada**: quien da la cuota por pagada es
/// el webhook `webhook-paypal`, que es lo único que la base deja escribir. Por
/// eso al volver se ofrece «Ya pagué» en vez de darlo por hecho: PayPal tarda
/// unos segundos en avisar.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  DriverSubscription _cuota = const DriverSubscription.sinPagar();
  bool _cargando = true;
  bool _pagando = false;
  String? _error;

  /// Se abrió PayPal y todavía no consta el pago. Cambia el texto del botón:
  /// quien acaba de pagar quiere «ya pagué», no «pagar» otra vez.
  bool _vuelveDePagar = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final cuota = await RideService.instance.miSuscripcion();
      if (!mounted) return;
      setState(() {
        _cuota = cuota;
        _cargando = false;
        _error = null;
        if (cuota.vigente) _vuelveDePagar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos consultar tu cuota.';
        _cargando = false;
      });
    }
  }

  Future<void> _pagar() async {
    setState(() {
      _pagando = true;
      _error = null;
    });
    try {
      final suscripcion = await PaymentsService.instance.abrirSuscripcion();
      final url = Uri.tryParse(suscripcion.aprobarEn);
      if (url == null) throw const RideException('PayPal devolvió un enlace roto.');

      final abrio = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() {
        _pagando = false;
        _vuelveDePagar = abrio;
        if (!abrio) _error = 'No pudimos abrir PayPal en este teléfono.';
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _pagando = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuota mensual')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: AppTheme.spaceMd),
                  ],
                  _Estado(cuota: _cuota),
                  const SizedBox(height: AppTheme.spaceLg),
                  const _QueIncluye(),
                  const SizedBox(height: AppTheme.spaceLg),
                  _Boton(
                    cuota: _cuota,
                    pagando: _pagando,
                    vuelveDePagar: _vuelveDePagar,
                    onPagar: _pagar,
                    onRevisar: _cargar,
                  ),
                  if (_cuota.tienePagoAMedias) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    _Aviso(
                      texto: 'Dejaste un pago a medias en PayPal '
                          '(${_cuota.pagoSinTerminar}). Mientras no lo '
                          'apruebes no cuenta como pagado.',
                    ),
                  ],
                  if (_vuelveDePagar && !_cuota.vigente) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    _Aviso(
                      texto: 'PayPal puede tardar unos segundos en confirmarnos '
                          'el pago. Si acabas de pagar, toca «Ya pagué».',
                    ),
                  ],
                  if (_cuota.referenciaExterna != null) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    _Referencia(id: _cuota.referenciaExterna!),
                  ],
                ],
              ),
            ),
    );
  }
}

/// El estado, en grande: es lo único que el chofer viene a mirar.
class _Estado extends StatelessWidget {
  const _Estado({required this.cuota});

  final DriverSubscription cuota;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    final (Color color, String titulo, String detalle) = switch (cuota) {
      _ when cuota.vigente && cuota.esCortesia => (
          ride.info,
          'Mes de cortesía',
          'Te regalamos el primer mes por ya estar con nosotros. '
              '${_restante(cuota)} Después son \$15 al mes.',
        ),
      _ when cuota.porVencer => (
          ride.danger,
          'Se te acaba pronto',
          '${_restante(cuota)} Renuévala para no quedarte sin recibir viajes.',
        ),
      _ when cuota.vigente => (
          ride.success,
          'Al día',
          '${_restante(cuota)} Puedes recibir viajes con normalidad.',
        ),
      _ when cuota.caducada => (
          ride.danger,
          'Se te venció',
          'Mientras no la renueves no te llegan solicitudes ni puedes '
              'ponerte en línea.',
        ),
      _ => (
          ride.danger,
          'Sin pagar',
          'Necesitas la cuota mensual para empezar a recibir viajes.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ride.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TU CUOTA',
            style: TextStyle(
              fontSize: AppText.micro,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            titulo,
            style: AppTheme.display(
              AppText.h1,
              color: ride.ink,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            style: TextStyle(
              fontSize: AppText.small,
              height: 1.45,
              color: ride.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// «Te quedan 12 días (hasta el 9 de octubre).»
  static String _restante(DriverSubscription cuota) {
    final dias = cuota.diasRestantes;
    final hasta = cuota.vigenteHasta;
    if (dias == null || hasta == null) return '';
    final cuantos = dias == 1 ? 'Te queda 1 día' : 'Te quedan $dias días';
    return '$cuantos (hasta el ${_fecha(hasta)}).';
  }

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static String _fecha(DateTime d) => '${d.day} de ${_meses[d.month - 1]}';
}

class _QueIncluye extends StatelessWidget {
  const _QueIncluye();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '\$15',
                style: AppTheme.display(
                  AppText.h1,
                  color: ride.ink,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'USD al mes',
                  style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w600,
                    color: ride.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceMd),
          const _Punto('Recibes las solicitudes de tu zona'),
          const _Punto('Te puedes poner en línea cuando quieras'),
          const _Punto('Sin límite de viajes: lo que ganes es tuyo'),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'Se cobra solo cada mes. Puedes darla de baja desde PayPal cuando '
            'quieras, y sigues trabajando hasta que termine el mes que ya '
            'pagaste.',
            style: TextStyle(
              fontSize: AppText.label,
              height: 1.45,
              color: ride.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: ride.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: AppText.small,
                height: 1.35,
                color: ride.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.cuota,
    required this.pagando,
    required this.vuelveDePagar,
    required this.onPagar,
    required this.onRevisar,
  });

  final DriverSubscription cuota;
  final bool pagando;
  final bool vuelveDePagar;
  final VoidCallback onPagar;
  final VoidCallback onRevisar;

  @override
  Widget build(BuildContext context) {
    // Al que ya está al día no se le ofrece pagar otra vez: pagaría doble.
    // Salvo que tenga un pago a medias, que sí conviene que termine o que se
    // entere de que quedó colgado.
    if (cuota.vigente && !cuota.esCortesia && !cuota.tienePagoAMedias) {
      return OutlinedButton.icon(
        onPressed: onRevisar,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar estado'),
      );
    }

    if (vuelveDePagar) {
      return FilledButton.icon(
        onPressed: onRevisar,
        icon: const Icon(Icons.check),
        label: const Text('Ya pagué'),
      );
    }

    return FilledButton.icon(
      onPressed: pagando ? null : onPagar,
      icon: pagando
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.account_balance_wallet_outlined),
      label: Text(
        cuota.tienePagoAMedias
            ? 'Terminar el pago'
            : cuota.esCortesia
                ? 'Pagar por adelantado'
                : cuota.caducada
                    ? 'Renovar por \$15'
                    : 'Pagar \$15 con PayPal',
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ride.infoSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 18, color: ride.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.4,
                color: ride.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El id de PayPal. No es adorno: cuando un chofer dice que pagó y no le
/// consta, es lo primero que se le pide para buscar el cobro.
class _Referencia extends StatelessWidget {
  const _Referencia({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Text(
      'Referencia de PayPal: $id',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: AppText.micro, color: ride.inkFaint),
    );
  }
}
