/// Validaciones de formularios en español, compartidas por login y registro.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final RegExp _phone = RegExp(r'^[0-9+\s-]{7,15}$');
  static final RegExp _plate = RegExp(r'^[A-Z]{3}-?[0-9]{3,4}$');

  static String? required(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    return null;
  }

  static String? name(String? value) {
    final vacio = required(value, campo: 'El nombre');
    if (vacio != null) return vacio;
    if (value!.trim().length < 3) return 'Ingresa tu nombre completo';
    return null;
  }

  static String? email(String? value) {
    final vacio = required(value, campo: 'El correo');
    if (vacio != null) return vacio;
    if (!_email.hasMatch(value!.trim())) return 'Ingresa un correo válido';
    return null;
  }

  static String? phone(String? value) {
    final vacio = required(value, campo: 'El teléfono');
    if (vacio != null) return vacio;
    if (!_phone.hasMatch(value!.trim())) return 'Ingresa un teléfono válido';
    return null;
  }

  static String? password(String? value) {
    final vacio = required(value, campo: 'La contraseña');
    if (vacio != null) return vacio;
    if (value!.length < 8) return 'Usa al menos 8 caracteres';
    if (!value.contains(RegExp(r'[A-Za-z]')) ||
        !value.contains(RegExp(r'[0-9]'))) {
      return 'Combina letras y números';
    }
    return null;
  }

  /// Contraseña definitiva de una cuenta administrativa: mínimo 10 caracteres,
  /// igual que `/api/change-password` en WEB-RIDE.
  static String? adminPassword(String? value) {
    final vacio = required(value, campo: 'La contraseña');
    if (vacio != null) return vacio;
    if (value!.length < 10) return 'Usa al menos 10 caracteres';
    if (!value.contains(RegExp(r'[A-Za-z]')) ||
        !value.contains(RegExp(r'[0-9]'))) {
      return 'Combina letras y números';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Las contraseñas no coinciden';
    return null;
  }

  static String? plate(String? value) {
    final vacio = required(value, campo: 'La placa');
    if (vacio != null) return vacio;
    if (!_plate.hasMatch(value!.trim().toUpperCase())) {
      return 'Formato inválido (ej. PDC-1234)';
    }
    return null;
  }

  static String? year(String? value) {
    final vacio = required(value, campo: 'El año');
    if (vacio != null) return vacio;
    final year = int.tryParse(value!.trim());
    final now = DateTime.now().year;
    if (year == null || year < 2005 || year > now + 1) {
      return 'Año entre 2005 y ${now + 1}';
    }
    return null;
  }
}
