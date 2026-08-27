import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/ride_colors.dart';

/// Campo del formulario de autenticación.
///
/// Etiqueta encima y caja de 56 px de alto. La web los tenía a 13 px de texto
/// y 10 px de radio, medidas de escritorio: en el teléfono el texto quedaba
/// chico para escribir y las esquinas casi rectas.
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
        style: TextStyle(fontSize: AppText.body, color: context.ride.ink),
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}

/// Campo de contraseña con el botón de ver / ocultar.
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
    final ride = context.ride;

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
        style: TextStyle(fontSize: AppText.body, color: ride.ink),
        decoration: InputDecoration(
          hintText: widget.hint,
          // Un icono con área de toque propia en vez del "Ver" de 10 px que
          // venía de la web: con el pulgar era casi imposible acertarle.
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            iconSize: 22,
            color: ride.inkMuted,
            tooltip: _obscure ? 'Ver contraseña' : 'Ocultar contraseña',
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              color: context.ride.inkMuted,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
