import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../core/validators.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/ride_text_field.dart';

/// Los tres formularios de «mi cuenta»: datos, correo y contraseña.
///
/// Van en pantallas completas y no en hojas: los tres piden teclado y una hoja
/// que se encoge hasta la mitad al abrirse el teclado deja los campos donde no
/// se ven.
///
/// Los tres comparten estructura y por eso comparten [_Formulario]: cabecera,
/// campos, un aviso de error y un botón que se bloquea mientras trabaja.

/// Cambiar el nombre y el teléfono.
class EditarDatosScreen extends StatefulWidget {
  const EditarDatosScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<EditarDatosScreen> createState() => _EditarDatosScreenState();
}

class _EditarDatosScreenState extends State<EditarDatosScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.user.name);
  late final _telefono = TextEditingController(text: widget.user.phone);

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService.instance.actualizarDatos(
        nombre: _nombre.text,
        telefono: _telefono.text,
      );
      if (!mounted) return;
      // El mensajero se toma antes de cerrar: después de `pop` este contexto
      // ya no cuelga de ningún Scaffold y el aviso no llegaría a verse.
      final aviso = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      aviso.showSnackBar(
        const SnackBar(content: Text('Datos actualizados')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Formulario(
      titulo: 'Mis datos',
      bajada: 'Así te ven las personas con las que viajas.',
      formKey: _form,
      error: _error,
      trabajando: _guardando,
      accion: 'Guardar cambios',
      onAccion: _guardar,
      campos: [
        RideTextField(
          label: 'Nombre completo',
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          validator: Validators.name,
          enabled: !_guardando,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        RideTextField(
          label: 'Teléfono',
          controller: _telefono,
          hint: '09XXXXXXXX',
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
          ],
          validator: Validators.phone,
          enabled: !_guardando,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
          onSubmitted: (_) => _guardar(),
        ),
        const SizedBox(height: 14),
        _Nota(
          'El teléfono es lo que ve tu chofer —o tu pasajero— para poder '
          'llamarte durante el viaje.',
        ),
      ],
    );
  }
}

/// Cambiar el correo de la cuenta.
class CambiarCorreoScreen extends StatefulWidget {
  const CambiarCorreoScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<CambiarCorreoScreen> createState() => _CambiarCorreoScreenState();
}

class _CambiarCorreoScreenState extends State<CambiarCorreoScreen> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();

  bool _enviando = false;
  String? _error;
  bool _enviado = false;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await AuthService.instance.cambiarCorreo(
        nuevoCorreo: _correo.text,
        contrasena: _contrasena.text,
      );
      if (!mounted) return;
      setState(() => _enviado = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enviado) {
      return _Confirmacion(
        icono: Icons.mark_email_unread_outlined,
        titulo: 'Revisa tu correo',
        detalle:
            'Te enviamos un enlace a ${_correo.text.trim()}. Tu cuenta seguirá '
            'usando ${widget.user.email} hasta que lo abras y confirmes el '
            'cambio.',
      );
    }

    return _Formulario(
      titulo: 'Cambiar correo',
      bajada: 'Ahora entras con ${widget.user.email}.',
      formKey: _form,
      error: _error,
      trabajando: _enviando,
      accion: 'Enviar confirmación',
      onAccion: _enviar,
      campos: [
        RideTextField(
          label: 'Correo nuevo',
          controller: _correo,
          hint: 'tucorreo@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          validator: Validators.email,
          enabled: !_enviando,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 16),
        RidePasswordField(
          label: 'Tu contraseña actual',
          controller: _contrasena,
          textInputAction: TextInputAction.done,
          validator: (v) =>
              Validators.required(v, campo: 'La contraseña'),
          enabled: !_enviando,
          onSubmitted: (_) => _enviar(),
        ),
        const SizedBox(height: 14),
        _Nota(
          'Pedimos la contraseña porque, sin ella, quien agarre tu teléfono '
          'desbloqueado podría llevarse la cuenta a otro correo.',
        ),
      ],
    );
  }
}

/// Cambiar la contraseña.
class CambiarContrasenaScreen extends StatefulWidget {
  const CambiarContrasenaScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<CambiarContrasenaScreen> createState() =>
      _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState extends State<CambiarContrasenaScreen> {
  final _form = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService.instance.cambiarContrasena(
        actual: _actual.text,
        nueva: _nueva.text,
      );
      if (!mounted) return;
      final aviso = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      aviso.showSnackBar(
        const SnackBar(content: Text('Tu contraseña quedó actualizada')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Las cuentas administrativas piden diez caracteres, el resto ocho: es la
    // misma regla que aplica el servidor.
    final validar = widget.user.role.isAdministrative
        ? Validators.adminPassword
        : Validators.password;

    return _Formulario(
      titulo: 'Cambiar contraseña',
      bajada: 'La necesitarás la próxima vez que inicies sesión.',
      formKey: _form,
      error: _error,
      trabajando: _guardando,
      accion: 'Cambiar contraseña',
      onAccion: _guardar,
      campos: [
        RidePasswordField(
          label: 'Contraseña actual',
          controller: _actual,
          validator: (v) => Validators.required(v, campo: 'La contraseña'),
          enabled: !_guardando,
        ),
        const SizedBox(height: 16),
        RidePasswordField(
          label: 'Contraseña nueva',
          controller: _nueva,
          validator: validar,
          enabled: !_guardando,
        ),
        const SizedBox(height: 16),
        RidePasswordField(
          label: 'Repite la nueva',
          controller: _repetir,
          textInputAction: TextInputAction.done,
          validator: (v) => Validators.confirmPassword(v, _nueva.text),
          enabled: !_guardando,
          onSubmitted: (_) => _guardar(),
        ),
      ],
    );
  }
}

/// Esqueleto común de los tres formularios.
class _Formulario extends StatelessWidget {
  const _Formulario({
    required this.titulo,
    required this.bajada,
    required this.formKey,
    required this.campos,
    required this.error,
    required this.trabajando,
    required this.accion,
    required this.onAccion,
  });

  final String titulo;
  final String bajada;
  final GlobalKey<FormState> formKey;
  final List<Widget> campos;
  final String? error;
  final bool trabajando;
  final String accion;
  final VoidCallback onAccion;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              bajada,
              style: TextStyle(
                fontSize: AppText.small,
                height: 1.45,
                color: ride.inkMuted,
              ),
            ),
            const SizedBox(height: 24),
            ...campos,
            if (error != null) ...[
              const SizedBox(height: 18),
              ErrorBanner(message: error!),
            ],
            const SizedBox(height: 26),
            FilledButton(
              onPressed: trabajando ? null : onAccion,
              child: trabajando ? const ButtonSpinner() : Text(accion),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla de «ya está, ahora te toca a ti»: el cambio de correo no termina
/// aquí, termina en la bandeja de entrada.
class _Confirmacion extends StatelessWidget {
  const _Confirmacion({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 56, color: ride.success),
            const SizedBox(height: 22),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: AppTheme.display(
                AppText.h1,
                color: ride.ink,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.small,
                height: 1.55,
                color: ride.inkMuted,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Entendido'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explicación al pie de un campo.
class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 17, color: ride.inkFaint),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: AppText.label,
              height: 1.5,
              color: ride.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
