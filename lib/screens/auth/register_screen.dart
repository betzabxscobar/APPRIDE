import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/validators.dart';
import '../../models/user_role.dart';
import '../../models/vehicle.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_text_field.dart';
import '../../widgets/role_selector.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Solo para conductores.
  final _vehicleController = TextEditingController();
  final _plateController = TextEditingController();
  final _yearController = TextEditingController();

  late UserRole _role = widget.role;
  bool _acceptedTerms = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _vehicleController.dispose();
    _plateController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      setState(() => _error = 'Debes aceptar los términos para continuar');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await AuthService.instance.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        password: _passwordController.text,
        role: _role,
        vehicle: _role.isDriver
            ? Vehicle(
                model: _vehicleController.text.trim(),
                plate: _plateController.text.trim().toUpperCase(),
                year: int.parse(_yearController.text.trim()),
              )
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              const Text(
                'Únete a Ride',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Elige tu rol y completa tus datos. Toma menos de dos minutos.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 20),
              RoleSwitch(
                value: _role,
                enabled: !_submitting,
                onChanged: (role) => setState(() {
                  _role = role;
                  _error = null;
                }),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Tus datos'),
              const SizedBox(height: 14),
              RideTextField(
                label: 'Nombre completo',
                hint: 'Andrea Salazar',
                icon: Icons.person_outline,
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: Validators.name,
                enabled: !_submitting,
              ),
              const SizedBox(height: 16),
              RideTextField(
                label: 'Correo electrónico',
                hint: 'tu@correo.com',
                icon: Icons.mail_outline,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
                enabled: !_submitting,
              ),
              const SizedBox(height: 16),
              RideTextField(
                label: 'Teléfono',
                hint: '0991234567',
                icon: Icons.phone_outlined,
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
                enabled: !_submitting,
              ),
              const SizedBox(height: 16),
              RidePasswordField(
                label: 'Contraseña',
                hint: 'Mínimo 8 caracteres',
                controller: _passwordController,
                validator: Validators.password,
                enabled: !_submitting,
              ),
              const SizedBox(height: 16),
              RidePasswordField(
                label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña',
                controller: _confirmController,
                validator: (v) => Validators.confirmPassword(
                  v,
                  _passwordController.text,
                ),
                textInputAction: TextInputAction.done,
                enabled: !_submitting,
              ),
              // Los campos del vehículo solo aplican al rol conductor.
              if (_role.isDriver) ...[
                const SizedBox(height: 28),
                const _SectionTitle('Tu vehículo'),
                const SizedBox(height: 4),
                const Text(
                  'Verificamos cada vehículo antes de aprobar viajes.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 14),
                RideTextField(
                  label: 'Marca y modelo',
                  hint: 'Toyota Corolla',
                  icon: Icons.directions_car_outlined,
                  controller: _vehicleController,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      Validators.required(v, campo: 'El vehículo'),
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: RideTextField(
                        label: 'Placa',
                        hint: 'PDC-1234',
                        icon: Icons.badge_outlined,
                        controller: _plateController,
                        textCapitalization: TextCapitalization.characters,
                        validator: Validators.plate,
                        enabled: !_submitting,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: RideTextField(
                        label: 'Año',
                        hint: '2021',
                        controller: _yearController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        validator: Validators.year,
                        enabled: !_submitting,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              _TermsCheckbox(
                value: _acceptedTerms,
                enabled: !_submitting,
                onChanged: (value) => setState(() {
                  _acceptedTerms = value;
                  _error = null;
                }),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const ButtonSpinner()
                    : Text('Crear cuenta de ${_role.displayName.toLowerCase()}'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '¿Ya tienes cuenta?',
                    style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
                  ),
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Inicia sesión'),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const Expanded(
              child: Text(
                'Acepto los términos, la política de privacidad y las normas '
                'de seguridad de Ride.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
