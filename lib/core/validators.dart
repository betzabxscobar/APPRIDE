/// Validaciones de formularios en español, compartidas por login y registro.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  /// Placa de auto: tres letras y tres o cuatro dígitos (PDC-1234).
  static final RegExp _plateCar = RegExp(r'^[A-Z]{3}-?[0-9]{3,4}$');

  /// Placa de moto: dos letras, tres dígitos y una letra final (IA-123A). La
  /// letra final es opcional porque las placas viejas no la traen, y rechazar
  /// la placa real de un chofer es peor que aceptar una rara de más.
  static final RegExp _plateMoto = RegExp(r'^[A-Z]{2}-?[0-9]{3}[A-Z]?$');

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

  /// Teléfono ecuatoriano. Acepta celular (09 + ocho dígitos) y convencional
  /// (02 a 07 + siete dígitos), escrito con o sin +593, espacios o guiones.
  static String? phone(String? value) {
    final vacio = required(value, campo: 'El teléfono');
    if (vacio != null) return vacio;

    final n = normalizarTelefono(value!);
    if (RegExp(r'^09[0-9]{8}$').hasMatch(n)) return null;
    if (RegExp(r'^0[2-7][0-9]{7}$').hasMatch(n)) return null;
    return 'Ingresa un celular (09…) o convencional (02…)';
  }

  /// Deja el teléfono en formato nacional: quita separadores y cambia el
  /// prefijo +593 por el 0 con el que se marca dentro del país.
  static String normalizarTelefono(String value) {
    var n = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+593')) {
      n = n.substring(4);
    } else if (n.startsWith('593')) {
      n = n.substring(3);
    } else {
      return n;
    }
    // Escrito como +593 9…, sin el cero nacional.
    return n.startsWith('0') ? n : '0$n';
  }

  /// Misma regla que `/api/register` en WEB-RIDE: mínimo 8 caracteres.
  static String? password(String? value) {
    final vacio = required(value, campo: 'La contraseña');
    if (vacio != null) return vacio;
    if (value!.length < 8) return 'Usa al menos 8 caracteres';
    return null;
  }

  /// Contraseña definitiva de una cuenta administrativa: mínimo 10 caracteres,
  /// igual que `/api/change-password` en WEB-RIDE.
  static String? adminPassword(String? value) {
    final vacio = required(value, campo: 'La contraseña');
    if (vacio != null) return vacio;
    if (value!.length < 10) return 'Usa al menos 10 caracteres';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Las contraseñas no coinciden';
    return null;
  }

  /// Placa de cualquier vehículo: sirve auto o moto.
  static String? plate(String? value) => plateFor(value, null);

  /// Placa según el tipo de vehículo del catálogo (`moto`, `estandar`,
  /// `confort`, `xl`). Con `categoria` en null acepta cualquiera de los dos
  /// formatos, para cuando todavía no se sabe qué vehículo es.
  static String? plateFor(String? value, String? categoria) {
    final vacio = required(value, campo: 'La placa');
    if (vacio != null) return vacio;

    final t = value!.trim().toUpperCase();
    final esMoto = categoria == 'moto';
    if (esMoto) {
      if (!_plateMoto.hasMatch(t)) return 'Formato de moto inválido (ej. IA-123A)';
      return null;
    }
    if (categoria == null) {
      if (_plateCar.hasMatch(t) || _plateMoto.hasMatch(t)) return null;
      return 'Formato inválido (ej. PDC-1234)';
    }
    if (!_plateCar.hasMatch(t)) return 'Formato inválido (ej. PDC-1234)';
    return null;
  }

  /// Cédula ecuatoriana: provincia, tipo y dígito verificador.
  ///
  /// El mismo algoritmo que `cedula_ecuatoriana_valida()` en Postgres. Está
  /// repetido a propósito: sirve para avisar mientras se escribe, sin ir al
  /// servidor. **La que manda es la de la base**, que es la que no se puede
  /// saltar manipulando la app.
  static String? cedula(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (v.length != 10) return 'La cédula tiene diez dígitos';
    if (!_provinciaValida(v)) return 'Los dos primeros dígitos no son una provincia';
    if (int.parse(v[2]) > 5) return 'Eso parece un RUC, no una cédula';
    if (_modulo10(v.substring(0, 9)) != int.parse(v[9])) {
      return 'Esa cédula no existe. Revisa los dígitos.';
    }
    return null;
  }

  /// RUC ecuatoriano de trece dígitos: persona natural (tercer dígito 0-5),
  /// entidad pública (6) o sociedad privada (9).
  ///
  /// Comprueba la **estructura**, no que el RUC esté registrado en el SRI ni
  /// que esté activo. Para eso hay que consultarle al SRI.
  static String? ruc(String? value) {
    final vacio = required(value, campo: 'El RUC');
    if (vacio != null) return vacio;

    final v = value!.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.length != 13) return 'El RUC tiene trece dígitos';
    if (!_provinciaValida(v)) return 'Los dos primeros dígitos no son una provincia';

    // Los tres últimos son el establecimiento: la matriz es 001.
    if (int.parse(v.substring(10)) < 1) {
      return 'Los tres últimos dígitos son el establecimiento (001)';
    }

    final tipo = int.parse(v[2]);
    if (tipo <= 5) {
      // Persona natural: es una cédula con 001 detrás.
      if (_modulo10(v.substring(0, 9)) != int.parse(v[9])) {
        return 'Ese RUC no existe. Revisa los dígitos.';
      }
      return null;
    }
    if (tipo == 6) {
      if (_modulo11(v.substring(0, 8), const [3, 2, 7, 6, 5, 4, 3, 2]) !=
          int.parse(v[8])) {
        return 'Ese RUC no existe. Revisa los dígitos.';
      }
      return null;
    }
    if (tipo == 9) {
      if (_modulo11(v.substring(0, 9), const [4, 3, 2, 7, 6, 5, 4, 3, 2]) !=
          int.parse(v[9])) {
        return 'Ese RUC no existe. Revisa los dígitos.';
      }
      return null;
    }
    return 'El tercer dígito no corresponde a ningún tipo de RUC';
  }

  /// Provincia válida: 01 a 24, más el 30 de los ecuatorianos en el exterior.
  static bool _provinciaValida(String v) {
    final p = int.parse(v.substring(0, 2));
    return (p >= 1 && p <= 24) || p == 30;
  }

  /// Dígito verificador de cédula: duplica las posiciones pares y resta nueve
  /// si se pasa de nueve.
  static int _modulo10(String base) {
    var suma = 0;
    for (var i = 0; i < base.length; i++) {
      var d = int.parse(base[i]);
      if (i % 2 == 0) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      suma += d;
    }
    return (10 - (suma % 10)) % 10;
  }

  /// Dígito verificador de RUC público y de sociedad, con sus coeficientes.
  static int _modulo11(String base, List<int> coeficientes) {
    var suma = 0;
    for (var i = 0; i < base.length; i++) {
      suma += int.parse(base[i]) * coeficientes[i];
    }
    final residuo = suma % 11;
    return residuo == 0 ? 0 : 11 - residuo;
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
