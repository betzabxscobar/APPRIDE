import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/ride_colors.dart';
import '../models/fleet.dart';
import '../services/fleet_service.dart';
import '../services/payments_service.dart';
import '../services/ride_service.dart';
import 'auth_feedback.dart';
import 'bank_logo.dart';

/// Las cuentas del chofer, para que el pasajero le transfiera.
///
/// Aquí no se mueve dinero. La app enseña el número, el pasajero lo copia y
/// hace la transferencia en la aplicación de su propio banco. Eso hay que
/// decirlo en la pantalla y no en una nota al pie: cambia quién responde si el
/// dinero no llega, y el pasajero tiene que saber que Ride no es el
/// intermediario.
///
/// Después de transferir, el pasajero adjunta el comprobante y avisa. Eso **no
/// da el viaje por pagado**: al chofer le llega el aviso, mira su banco y lo
/// confirma él, que es el único que puede verlo de verdad. Hasta entonces el
/// viaje no se cierra.
Future<void> mostrarHojaTransferencia(
  BuildContext context, {
  required String viajeId,
  required double monto,
  String? chofer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HojaTransferencia(
      viajeId: viajeId,
      monto: monto,
      chofer: chofer,
    ),
  );
}

class _HojaTransferencia extends StatefulWidget {
  const _HojaTransferencia({
    required this.viajeId,
    required this.monto,
    this.chofer,
  });

  final String viajeId;
  final double monto;
  final String? chofer;

  @override
  State<_HojaTransferencia> createState() => _HojaTransferenciaState();
}

class _HojaTransferenciaState extends State<_HojaTransferencia> {
  List<BankAccount> _cuentas = const [];
  bool _cargando = true;
  String? _error;

  /// La foto del comprobante, ya subida. Es la prueba que queda si más tarde
  /// se discute si el dinero se envió o no.
  String? _comprobante;
  bool _subiendo = false;
  bool _avisado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final cuentas = await FleetService.instance.cuentasDelChofer(widget.viajeId);
      if (!mounted) return;
      setState(() {
        _cuentas = cuentas;
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

  void _copiar(String texto, String que) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$que copiado'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _adjuntar() async {
    final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // El comprobante se lee en pantalla, no se imprime: a 1600 px se ve
      // perfecto y pesa una fracción de lo que sale de la cámara.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (foto == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final bytes = await foto.readAsBytes();
      final ruta = await PaymentsService.instance
          .subirComprobante(widget.viajeId, bytes);
      if (!mounted) return;
      setState(() {
        _comprobante = ruta;
        _subiendo = false;
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _error = e.message;
      });
    }
  }

  Future<void> _avisar() async {
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      await PaymentsService.instance.reportarTransferencia(
        widget.viajeId,
        comprobante: _comprobante,
      );
      if (!mounted) return;
      setState(() {
        _avisado = true;
        _subiendo = false;
      });
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transferir al chofer',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ride.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.chofer == null
                  ? 'Son \$${widget.monto.toStringAsFixed(2)}'
                  : 'Son \$${widget.monto.toStringAsFixed(2)} para ${widget.chofer}',
              style: TextStyle(color: ride.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ride.infoSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: ride.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La transferencia la haces tú, desde la app de tu banco. '
                      'Ride no recibe ni retiene este dinero: va directo a la '
                      'cuenta del chofer.',
                      style: TextStyle(fontSize: 12, color: ride.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              ErrorBanner(message: _error!)
            else if (_cuentas.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                decoration: BoxDecoration(
                  color: ride.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ride.border),
                ),
                child: Column(
                  children: [
                    Icon(Icons.account_balance_outlined,
                        size: 34, color: ride.inkFaint),
                    const SizedBox(height: 10),
                    Text(
                      'Este chofer no tiene cuentas registradas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ride.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Págale en efectivo, o pídele que agregue una cuenta desde '
                      'su perfil.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: ride.inkMuted),
                    ),
                  ],
                ),
              )
            else
              for (final cuenta in _cuentas) ...[
                _TarjetaCuenta(cuenta: cuenta, onCopiar: _copiar),
                const SizedBox(height: 12),
              ],
            // El paso que convierte esto en un cobro comprobable. Solo tiene
            // sentido si hay una cuenta a la que transferir.
            if (!_cargando && _error == null && _cuentas.isNotEmpty) ...[
              const SizedBox(height: 4),
              Divider(color: ride.border),
              const SizedBox(height: 10),
              Text(
                'Cuando ya hayas transferido',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: ride.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjunta el comprobante y avisa al chofer. Él revisa su banco y '
                'confirma; hasta entonces el viaje sigue abierto.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: ride.inkMuted),
              ),
              const SizedBox(height: 12),
              if (_avisado)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ride.successSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 20, color: ride.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Avisamos al chofer. Está revisando su banco.',
                          style: TextStyle(fontSize: 13, color: ride.ink),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _subiendo ? null : _adjuntar,
                  icon: Icon(
                    _comprobante == null
                        ? Icons.attach_file
                        : Icons.check_circle_outline,
                    size: 20,
                  ),
                  label: Text(
                    _comprobante == null
                        ? 'Adjuntar comprobante'
                        : 'Comprobante adjunto',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: _comprobante == null ? null : ride.success,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  // Sin comprobante no se avisa: es lo único que le queda al
                  // pasajero si luego el chofer dice que no le llegó.
                  onPressed: _subiendo || _comprobante == null ? null : _avisar,
                  icon: _subiendo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 20),
                  label: const Text('Ya transferí'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_avisado ? 'Cerrar' : 'Ahora no'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaCuenta extends StatelessWidget {
  const _TarjetaCuenta({required this.cuenta, required this.onCopiar});

  final BankAccount cuenta;
  final void Function(String texto, String que) onCopiar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ride.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BankLogo(banco: cuenta.bancoComoCatalogo),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cuenta.bancoNombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ride.ink,
                  ),
                ),
              ),
              Text(
                cuenta.tipoLabel,
                style: TextStyle(fontSize: 11, color: ride.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // El número es lo que se copia, así que se pone grande, con cifras de
          // ancho fijo para poder cotejarlo de un vistazo.
          InkWell(
            onTap: () => onCopiar(cuenta.numero, 'Número de cuenta'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: ride.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cuenta.numero,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: ride.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 20, color: ride.accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Dato(
            etiqueta: 'Titular',
            valor: cuenta.titular,
            onCopiar: () => onCopiar(cuenta.titular, 'Titular'),
          ),
          if (cuenta.cedulaTitular != null) ...[
            const SizedBox(height: 6),
            _Dato(
              etiqueta: 'Cédula',
              valor: cuenta.cedulaTitular!,
              onCopiar: () => onCopiar(cuenta.cedulaTitular!, 'Cédula'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.onCopiar,
  });

  final String etiqueta;
  final String valor;
  final VoidCallback onCopiar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            etiqueta,
            style: TextStyle(fontSize: 12, color: ride.inkFaint),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: TextStyle(fontSize: 13, color: ride.ink),
          ),
        ),
        IconButton(
          onPressed: onCopiar,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.copy_rounded, size: 17, color: ride.inkMuted),
          tooltip: 'Copiar $etiqueta',
        ),
      ],
    );
  }
}
