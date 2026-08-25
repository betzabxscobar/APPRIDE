import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';

/// Campo del formulario de autenticación.
///
/// Reproduce `.auth-box label` + `.auth-box input` de WEB-RIDE: etiqueta
/// pequeña en mayúscula de peso 700 sobre una caja blanca de borde suave.
class RideTextField extends StatelessWidget {
  const RideTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.enabled = true,
    this.autofillHints,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

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
        onFieldSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 13, color: AppColors.ink),
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}

/// Campo de contraseña con el botón de texto "Ver" / "Ocultar" del diseño web.
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
        style: const TextStyle(fontSize: 13, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIconConstraints: const BoxConstraints(minWidth: 58),
          suffixIcon: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Text(
                  _obscure ? 'Ver' : 'Ocultar',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF168FBC),
                  ),
                ),
              ),
            ),
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
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.fieldLabel,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
