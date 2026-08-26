import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/app_user.dart';
import '../models/user_role.dart';
import '../models/vehicle.dart';

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Servicio de autenticación sobre Supabase Auth.
///
/// Mantiene la misma interfaz que la versión en memoria que tenía la app: las
/// pantallas (`login_screen`, `register_screen`, `first_access_screen`,
/// `admin_dashboard_screen`, `account_sheet`) no cambiaron de contrato.
///
/// El rol se lee de `public.profiles`, no de `app_metadata` del token. En la
/// base real `app_metadata.role` está vacío y las políticas RLS resuelven el
/// rol con `current_user_role()`, que consulta la tabla.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Longitud mínima de la contraseña definitiva de una cuenta administrativa.
  static const int adminPasswordMinLength = 10;

  static const String _profileColumns =
      'id, email, full_name, phone, role, must_change_password, created_at';

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  AppUser? _currentUser;
  bool _isLoading = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  /// Restaura la sesión guardada al abrir la app y reacciona a los cambios de
  /// sesión (cierre, refresco de token, expiración).
  Future<void> bootstrap() async {
    _setLoading(true);
    try {
      if (_client.auth.currentSession != null) {
        _currentUser = await _loadProfile();
      }
    } catch (_) {
      await _client.auth.signOut();
      _currentUser = null;
    } finally {
      _setLoading(false);
    }

    _client.auth.onAuthStateChange.listen((state) {
      if (state.event == sb.AuthChangeEvent.signedOut) {
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  /// Inicia sesión con correo y contraseña.
  ///
  /// El rol no se elige al entrar: lo define la cuenta, y con él la app decide
  /// si abre el home de pasajero, el de conductor o el panel administrativo.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return _run(() async {
      try {
        await _client.auth.signInWithPassword(
          email: _normalize(email),
          password: password,
        );
      } on sb.AuthException catch (error) {
        throw AuthException(_translate(error.message));
      }

      final user = await _loadProfile();
      _currentUser = user;
      return user;
    });
  }

  /// Crea una cuenta nueva.
  ///
  /// Solo pasajero o conductor: el trigger `handle_new_user()` descarta
  /// cualquier rol administrativo que llegue desde aquí, así que el formulario
  /// no puede escalar privilegios ni aunque se manipule el cliente.
  ///
  /// Si el proyecto exige confirmar el correo, `signUp` no devuelve sesión y
  /// este método lanza [EmailConfirmationRequired].
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
    Vehicle? vehicle,
  }) async {
    return _run(() async {
      if (role.isAdministrative) {
        throw const AuthException(
          'Las cuentas administrativas no se crean desde la app',
        );
      }

      final sb.AuthResponse response;
      try {
        response = await _client.auth.signUp(
          email: _normalize(email),
          password: password,
          data: {
            'full_name': name.trim(),
            'phone': phone.trim(),
            'role': role.id,
          },
        );
      } on sb.AuthException catch (error) {
        throw AuthException(_translate(error.message));
      }

      if (response.session == null) {
        throw const EmailConfirmationRequired();
      }

      final user = await _loadProfile();
      _currentUser = user;
      return user;
    });
  }

  /// Primer acceso administrativo: reemplaza la contraseña temporal.
  ///
  /// Se hace con la sesión del propio usuario: `updateUser` cambia la clave en
  /// Auth y la política `profiles_update_own` permite bajar la bandera. No
  /// hace falta la clave `service_role`.
  Future<AppUser> changeInitialPassword(String password) async {
    return _run(() async {
      final user = _currentUser;
      if (user == null) {
        throw const AuthException('Debes iniciar sesión');
      }
      if (!user.role.isAdministrative) {
        throw const AuthException(
          'Este flujo es exclusivo para cuentas administrativas',
        );
      }
      if (password.length < adminPasswordMinLength) {
        throw const AuthException(
          'La nueva contraseña debe tener mínimo '
          '$adminPasswordMinLength caracteres',
        );
      }

      try {
        await _client.auth.updateUser(sb.UserAttributes(password: password));
      } on sb.AuthException catch (error) {
        // Supabase rechaza reutilizar la contraseña vigente.
        throw AuthException(_translate(error.message));
      }

      try {
        await _client.from('profiles').update({
          'must_change_password': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);
      } on sb.PostgrestException {
        throw const AuthException(
          'Cambiamos la contraseña pero no pudimos actualizar tu cuenta',
        );
      }

      final updated = await _loadProfile();
      _currentUser = updated;
      return updated;
    });
  }

  /// Pide el correo con el enlace para restablecer la contraseña.
  ///
  /// No revela si el correo existe: Supabase responde igual en ambos casos y
  /// la pantalla muestra siempre el mismo aviso, para no filtrar qué cuentas
  /// hay registradas.
  ///
  /// El enlace abre el navegador, no la app: allí se fija la contraseña nueva
  /// y después se vuelve aquí a iniciar sesión. Para que abriera la app harían
  /// falta *deep links*, que todavía no están configurados.
  Future<void> requestPasswordReset(String email) async {
    _setLoading(true);
    try {
      await _client.auth.resetPasswordForEmail(_normalize(email));
    } on sb.AuthException catch (error) {
      throw AuthException(_translate(error.message));
    } finally {
      _setLoading(false);
    }
  }

  /// Usuarios visibles para la sesión administrativa activa.
  ///
  /// No filtra en el cliente: las políticas RLS deciden qué filas llegan, así
  /// que un `admin` simplemente no recibe a los `superadmin`.
  Future<List<AppUser>> visibleUsers() async {
    final admin = _currentUser;
    if (admin == null || !admin.role.isAdministrative) {
      throw const AuthException('No tienes permiso para ver este contenido');
    }
    if (admin.mustChangePassword) {
      throw const AuthException('Primero debes cambiar tu contraseña temporal');
    }

    try {
      final rows = await _client
          .from('profiles')
          .select(_profileColumns)
          .order('created_at', ascending: false);
      return rows.map((row) => _toAppUser(row)).toList();
    } on sb.PostgrestException {
      throw const AuthException('No se pudieron cargar los usuarios');
    }
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _client.auth.signOut();
    } finally {
      _currentUser = null;
      _setLoading(false);
    }
  }

  /// Cambia el modo activo de la sesión (Modo conductor / Modo pasajero).
  ///
  /// Es un cambio local: no toca `profiles.role`. El trigger
  /// `prevent_role_self_edit()` impide que nadie se cambie el rol a sí mismo,
  /// que es justo lo que evita una escalada de privilegios. Al cerrar sesión
  /// la app vuelve al rol que tiene la cuenta en la base.
  void switchRole(UserRole role) {
    final user = _currentUser;
    if (user == null || user.role == role) return;
    if (user.role.isAdministrative || role.isAdministrative) {
      throw const AuthException(
        'Las cuentas administrativas no cambian de modo',
      );
    }
    if (role.isDriver && user.vehicle == null) {
      throw const AuthException(
        'Para conducir necesitas registrar tu vehículo primero',
      );
    }
    _currentUser = user.copyWith(role: role);
    notifyListeners();
  }

  /// Perfil del usuario de la sesión activa.
  Future<AppUser> _loadProfile() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('Tu sesión expiró. Vuelve a iniciar sesión');
    }

    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profiles')
          .select(_profileColumns)
          .eq('id', id)
          .maybeSingle();
    } on sb.PostgrestException {
      throw const AuthException('No pudimos cargar tu perfil');
    }

    if (row == null) {
      throw const AuthException('Tu cuenta no tiene un perfil asociado');
    }
    return _toAppUser(row);
  }

  AppUser _toAppUser(Map<String, dynamic> row) {
    final email = (row['email'] as String?) ?? '';
    final fullName = (row['full_name'] as String?)?.trim();
    final createdAt = row['created_at'] as String?;

    return AppUser(
      id: row['id'] as String,
      name: (fullName == null || fullName.isEmpty)
          ? email.split('@').first
          : fullName,
      email: email,
      phone: (row['phone'] as String?) ?? '',
      role: UserRole.fromId((row['role'] as String?) ?? 'passenger'),
      isVerified: true,
      mustChangePassword: (row['must_change_password'] as bool?) ?? false,
      createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    );
  }

  Future<AppUser> _run(Future<AppUser> Function() action) async {
    _setLoading(true);
    try {
      return await action();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  String _normalize(String email) => email.trim().toLowerCase();

  /// Traduce los mensajes de Supabase, que llegan en inglés.
  String _translate(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de entrar.';
    }
    if (normalized.contains('user already registered')) {
      return 'Este correo ya tiene una cuenta.';
    }
    if (normalized.contains('should be different from the old password')) {
      return 'Elige una contraseña distinta a la temporal.';
    }
    if (normalized.contains('password should be at least')) {
      return 'La contraseña es demasiado corta.';
    }
    if (normalized.contains('email rate limit exceeded')) {
      return 'Se alcanzó el límite de correos. Intenta más tarde.';
    }
    if (normalized.contains('for security purposes')) {
      return 'Espera unos segundos antes de reintentar.';
    }
    if (normalized.contains('database error saving new user')) {
      return 'Este correo no puede registrarse con ese rol.';
    }
    return message;
  }
}

/// El proyecto exige confirmar el correo: la cuenta quedó creada pero todavía
/// no hay sesión, así que la app debe pedirle al usuario que abra el enlace.
class EmailConfirmationRequired extends AuthException {
  const EmailConfirmationRequired()
      : super(
          'Te enviamos un correo de confirmación. '
          'Ábrelo para activar tu cuenta.',
        );
}
