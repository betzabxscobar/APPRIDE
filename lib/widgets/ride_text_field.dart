import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';

/// Campo de texto con etiqueta, ícono y estilo Ride.
class RideTextField extends StatelessWidget {
  const RideTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.enabled = true,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return _FieldWrapper(
      label: label,
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        enabled: enabled,
        autofillHints: autofillHints,
        style: const TextStyle(fontSize: 15, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: icon == null
              ? null
              : Icon(icon, size: 20, color: AppColors.inkMuted),
        ),
      ),
    );
  }
}

/// Campo de contraseña con botón para mostrar/ocultar.
class RidePasswordField extends StatefulWidget {
  const RidePasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.enabled = true,
    this.onSubmitted,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<RidePasswordField> createState() => _RidePasswordFieldState();
}

class _RidePasswordFieldState extends State<RidePasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return _FieldWrapper(
      label: widget.label,
      child: TextFormField(
        controller: widget.controller,
        validator: widget.validator,
        obscureText: _obscure,
        enabled: widget.enabled,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        autofillHints: widget.autofillHints,
        style: const TextStyle(fontSize: 15, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(
            Icons.lock_outline,
            size: 20,
            color: AppColors.inkMuted,
          ),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
              color: AppColors.inkMuted,
            ),
            tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
          ),
        ),
      ),
    );
  }
}

class _FieldWrapper extends StatelessWidget {
  const _FieldWrapper({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
