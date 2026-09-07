import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ride_colors.dart';
import '../../core/validators.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/bank_logo.dart';
import '../../widgets/ride_text_field.dart';

/// Las cuentas a las que el chofer quiere que le transfieran.
///
/// El pasajero copia el número y transfiere desde su propio banco. La app no
/// mueve el dinero: por eso aquí no hay saldo ni confirmación automática, y por
/// eso el chofer tiene que revisar su banco antes de dar un viaje por cobrado.
class BankAccountsScreen extends StatefulWidget {
  const BankAccountsScreen({super.key});

  @override
  State<BankAccountsScreen> createState() => _BankAccountsScreenState();
}

class _BankAccountsScreenState extends State<BankAccountsScreen> {
  List<BankAccount> _cuentas = const [];
  List<Bank> _bancos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final bancos = await FleetService.instance.bancos();
      final cuentas = await FleetService.instance.misCuentasBancarias();
      if (!mounted) return;
      setState(() {
        _bancos = bancos;
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

  Future<void> _abrirFormulario([BankAccount? cuenta]) async {
    if (_bancos.isEmpty) return;
    final guardada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioCuenta(bancos: _bancos, cuenta: cuenta),
    );
    if (guardada == true) await _cargar();
  }

  Future<void> _eliminar(BankAccount cuenta) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar esta cuenta?'),
        content: Text(
          'Los pasajeros dejarán de ver la cuenta ${cuenta.numero} de '
          '${cuenta.bancoNombre}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.ride.danger),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await FleetService.instance.eliminarCuentaBancaria(cuenta.id);
      await _cargar();
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas para cobrar')),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar cuenta'),
            ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                children: [
                  Text(
                    'El pasajero ve estas cuentas al terminar el viaje, copia el '
                    'número y transfiere desde su banco.',
                    style: TextStyle(color: ride.inkMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
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
                            'Ride no recibe ni reenvía este dinero: entra directo '
                            'a tu cuenta. Revisa tu banco antes de dar el viaje '
                            'por cobrado.',
                            style: TextStyle(fontSize: 12, color: ride.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 18),
                  if (_cuentas.isEmpty)
                    _SinCuentas(onAgregar: () => _abrirFormulario())
                  else
                    for (final cuenta in _cuentas) ...[
                      _FilaCuenta(
                        cuenta: cuenta,
                        onEditar: () => _abrirFormulario(cuenta),
                        onEliminar: () => _eliminar(cuenta),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }
}

class _SinCuentas extends StatelessWidget {
  const _SinCuentas({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: ride.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ride.border),
      ),
      child: Column(
        children: [
          Icon(Icons.account_balance_outlined, size: 40, color: ride.inkFaint),
          const SizedBox(height: 12),
          Text(
            'Todavía no tienes ninguna cuenta',
            style: TextStyle(fontWeight: FontWeight.w700, color: ride.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Sin una cuenta, tus pasajeros solo te pueden pagar en efectivo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ride.inkMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAgregar,
            icon: const Icon(Icons.add),
            label: const Text('Agregar la primera'),
          ),
        ],
      ),
    );
  }
}

class _FilaCuenta extends StatelessWidget {
  const _FilaCuenta({
    required this.cuenta,
    required this.onEditar,
    required this.onEliminar,
  });

  final BankAccount cuenta;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ride.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cuenta.predeterminada ? ride.accent : ride.border,
          width: cuenta.predeterminada ? 1.6 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BankLogo(banco: cuenta.bancoComoCatalogo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        cuenta.bancoNombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ride.ink,
                        ),
                      ),
                    ),
                    if (cuenta.predeterminada) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ride.accentSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Principal',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ride.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  cuenta.numero,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 0.6,
                    color: ride.ink,
                  ),
                ),
                Text(
                  '${cuenta.tipoLabel} · ${cuenta.titular}',
                  style: TextStyle(fontSize: 12, color: ride.inkMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'editar' ? onEditar() : onEliminar(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'editar', child: Text('Editar')),
              PopupMenuItem(value: 'eliminar', child: Text('Quitar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alta y edición de una cuenta. Devuelve `true` si se guardó.
class _FormularioCuenta extends StatefulWidget {
  const _FormularioCuenta({required this.bancos, this.cuenta});

  final List<Bank> bancos;
  final BankAccount? cuenta;

  @override
  State<_FormularioCuenta> createState() => _FormularioCuentaState();
}

class _FormularioCuentaState extends State<_FormularioCuenta> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _numero;
  late final TextEditingController _titular;
  late final TextEditingController _cedula;

  late String _banco;
  late String _tipo;
  late bool _predeterminada;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.cuenta != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cuenta;
    _numero = TextEditingController(text: c?.numero ?? '');
    _titular = TextEditingController(text: c?.titular ?? '');
    _cedula = TextEditingController(text: c?.cedulaTitular ?? '');
    _banco = c?.banco ?? widget.bancos.first.id;
    _tipo = c?.tipo ?? 'ahorros';
    _predeterminada = c?.predeterminada ?? true;
  }

  @override
  void dispose() {
    _numero.dispose();
    _titular.dispose();
    _cedula.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await FleetService.instance.guardarCuentaBancaria(
        banco: _banco,
        tipo: _tipo,
        numero: _numero.text,
        titular: _titular.text,
        cedulaTitular: _cedula.text.trim().isEmpty ? null : _cedula.text,
        predeterminada: _predeterminada,
        cuentaId: widget.cuenta?.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _esEdicion ? 'Editar cuenta' : 'Nueva cuenta',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: ride.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tiene que estar a tu nombre: el pasajero ve al titular antes '
                'de transferir.',
                style: TextStyle(fontSize: 12, color: ride.inkMuted),
              ),
              const SizedBox(height: 18),
              Text(
                'BANCO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: ride.inkFaint,
                ),
              ),
              const SizedBox(height: 8),
              for (final banco in widget.bancos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: _guardando ? null : () => setState(() => _banco = banco.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _banco == banco.id ? ride.accentSoft : ride.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _banco == banco.id ? ride.accent : ride.border,
                          width: _banco == banco.id ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          BankLogo(banco: banco, alto: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              banco.nombre,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: ride.ink,
                              ),
                            ),
                          ),
                          if (_banco == banco.id)
                            Icon(Icons.check_circle, size: 20, color: ride.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ahorros', label: Text('Ahorros')),
                  ButtonSegment(value: 'corriente', label: Text('Corriente')),
                ],
                selected: {_tipo},
                onSelectionChanged:
                    _guardando ? null : (v) => setState(() => _tipo = v.first),
              ),
              const SizedBox(height: 14),
              RideTextField(
                label: 'Número de cuenta',
                hint: '2100123456',
                controller: _numero,
                enabled: !_guardando,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: Validators.numeroDeCuenta,
              ),
              const SizedBox(height: 14),
              RideTextField(
                label: 'Titular de la cuenta',
                hint: 'Como aparece en tu banco',
                controller: _titular,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.words,
                validator: Validators.name,
              ),
              const SizedBox(height: 14),
              RideTextField(
                label: 'Cédula del titular (opcional)',
                hint: '1701234567',
                controller: _cedula,
                enabled: !_guardando,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                // Opcional, pero si la escribe tiene que ser real: es lo que el
                // pasajero coteja en la pantalla de su banco.
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? null : Validators.cedula(v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _predeterminada,
                onChanged:
                    _guardando ? null : (v) => setState(() => _predeterminada = v),
                title: const Text('Mostrarla primero'),
                subtitle: Text(
                  'Es la que el pasajero ve arriba',
                  style: TextStyle(fontSize: 12, color: ride.inkMuted),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: Text(_guardando ? 'Guardando…' : 'Guardar cuenta'),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
