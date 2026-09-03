import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ride_colors.dart';
import '../../models/fleet.dart';
import '../../services/fleet_service.dart';
import '../../services/ride_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_text_field.dart';

/// Cédula, código dactilar y licencia. Devuelve `true` si se guardó.
Future<bool?> mostrarFormularioIdentidad(
  BuildContext context, {
  DriverIdentity? identidad,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.ride.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FormularioIdentidad(identidad: identidad),
  );
}

class _FormularioIdentidad extends StatefulWidget {
  const _FormularioIdentidad({this.identidad});

  final DriverIdentity? identidad;

  @override
  State<_FormularioIdentidad> createState() => _FormularioIdentidadState();
}

class _FormularioIdentidadState extends State<_FormularioIdentidad> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cedula;
  late final TextEditingController _dactilar;

  LicenseType? _licencia;
  DateTime? _caduca;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.identidad;
    _cedula = TextEditingController(text: i?.cedula ?? '');
    _dactilar = TextEditingController(text: i?.codigoDactilar ?? '');
    _licencia = i?.licencia;
    _caduca = i?.licenciaCaducaEl;
  }

  @override
  void dispose() {
    _cedula.dispose();
    _dactilar.dispose();
    super.dispose();
  }

  /// El mismo algoritmo que `cedula_ecuatoriana_valida()` en Postgres.
  ///
  /// Está repetido a propósito, y solo aquí: sirve para avisar mientras se
  /// escribe, sin ir al servidor. **La que manda es la de la base**, que es la
  /// que no se puede saltar manipulando la app.
  String? _validarCedula(String? valor) {
    final v = (valor ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (v.length != 10) return 'La cédula tiene diez dígitos';

    final provincia = int.parse(v.substring(0, 2));
    if (!(provincia >= 1 && provincia <= 24) && provincia != 30) {
      return 'Los dos primeros dígitos no son una provincia';
    }
    if (int.parse(v[2]) > 5) return 'Eso parece un RUC, no una cédula';

    var suma = 0;
    for (var i = 0; i < 9; i++) {
      var d = int.parse(v[i]);
      if (i % 2 == 0) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      suma += d;
    }
    if ((10 - (suma % 10)) % 10 != int.parse(v[9])) {
      return 'Esa cédula no existe. Revisa los dígitos.';
    }
    return null;
  }

  String? _validarDactilar(String? valor) {
    final v = (valor ?? '').replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-Z][0-9]{4}[A-Z][0-9]{4}$').hasMatch(v)) {
      return 'Va como en el reverso: V1234I5678';
    }
    return null;
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _caduca ?? DateTime(hoy.year + 5, hoy.month, hoy.day),
      // Desde mañana: una licencia que caduca hoy ya no sirve para trabajar.
      firstDate: hoy.add(const Duration(days: 1)),
      lastDate: DateTime(hoy.year + 15),
      helpText: 'Caducidad de la licencia',
    );
    if (elegida != null) setState(() => _caduca = elegida);
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_licencia == null) {
      setState(() => _error = 'Elige el tipo de licencia que tienes');
      return;
    }
    if (_caduca == null) {
      setState(() => _error = 'Falta hasta cuándo vale tu licencia');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await FleetService.instance.registrarIdentidad(
        cedula: _cedula.text,
        codigoDactilar: _dactilar.text,
        licencia: _licencia!,
        licenciaCaducaEl: _caduca!,
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
    final ride = context.ride;

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
                'Tus datos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ride.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tienen que coincidir con la cédula y la licencia que subas: '
                'la administración los compara antes de aprobarte.',
                style: TextStyle(fontSize: 12, color: ride.inkMuted),
              ),
              const SizedBox(height: 18),
              RideTextField(
                label: 'Cédula',
                hint: '1710034065',
                controller: _cedula,
                enabled: !_guardando,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: _validarCedula,
              ),
              const SizedBox(height: 14),
              RideTextField(
                label: 'Código dactilar',
                hint: 'V1234I5678',
                controller: _dactilar,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [LengthLimitingTextInputFormatter(10)],
                validator: _validarDactilar,
              ),
              const SizedBox(height: 6),
              Text(
                'Está en el reverso de tu cédula, arriba a la derecha.',
                style: TextStyle(fontSize: 11.5, color: ride.inkMuted),
              ),
              const SizedBox(height: 18),
              Text(
                'Tipo de licencia',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ride.ink,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<LicenseType>(
                initialValue: _licencia,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ride.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ride.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ride.border),
                  ),
                ),
                hint: const Text('Elige la que tienes'),
                items: [
                  for (final l in LicenseType.values)
                    DropdownMenuItem(
                      value: l,
                      child: Text(
                        l.label,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _licencia = v),
              ),
              const SizedBox(height: 6),
              Text(
                'Para llevar pasajeros hace falta licencia profesional. Con una '
                'B solo podrías registrar el auto, no ponerlo en servicio.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: ride.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: _guardando ? null : _elegirFecha,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  decoration: BoxDecoration(
                    color: ride.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ride.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, size: 19, color: ride.inkMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _caduca == null
                              ? 'Caducidad de la licencia'
                              : 'Caduca el ${_fecha(_caduca!)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: _caduca == null ? ride.inkMuted : ride.ink,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: ride.inkMuted),
                    ],
                  ),
                ),
              ),
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
                child: Text(_guardando ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
