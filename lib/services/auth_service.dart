import 'package:flutter/foundation.dart';

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

/// Credenciales + perfil guardados en memoria.
class _Account {
  _Account({required this.password, required this.user});
  String password;
  AppUser user;
}

/// Servicio de autenticación en memoria.
///
/// Reproduce las reglas del backend local de WEB-RIDE (`server.mjs`): mismos
/// roles, mismas validaciones y mismo flujo de primer acceso administrativo.
/// Cuando exista Supabase solo hay que reemplazar el cuerpo de [signIn],
/// [register], [changeInitialPassword] y [signOut]: la interfaz no cambia.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const Duration _latency = Duration(milliseconds: 900);

  /// Contraseña temporal con la que se entregan las cuentas administrativas
  /// mientras la autenticación es local. En WEB-RIDE la genera al azar
  /// `scripts/crear-cuentas-administrativas.mjs`.
  static const String temporaryAdminPassword = 'Ride-Temporal2026';

  /// Longitud mínima de la contraseña definitiva de una cuenta administrativa,
  /// igual que en `/api/change-password`.
  static const int adminPasswordMinLength = 10;

  final Map<String, _Account> _accounts = {
    'pasajero@ride.app': _Account(
      password: 'Ride1234',
      user: AppUser(
        id: 'demo-passenger',
        name: 'Andrea Salazar',
        email: 'pasajero@ride.app',
        phone: '0991234567',
        role: UserRole.passenger,
        isVerified: true,
        createdAt: DateTime(2026, 1, 12),
      ),
    ),
    'conductor@ride.app': _Account(
      password: 'Ride1234',
      user: AppUser(
        id: 'demo-driver',
        name: 'Carlos Andrade',
        email: 'conductor@ride.app',
        phone: '0987654321',
        role: UserRole.driver,
        isVerified: true,
        vehicle: const Vehicle(
          model: 'Toyota Corolla',
          plate: 'PDC-1234',
          year: 2021,
        ),
        createdAt: DateTime(2026, 1, 20),
      ),
    ),
    // Equipo administrativo, el mismo que provisiona WEB-RIDE.
    ..._administrativeAccounts(),
  };

  static Map<String, _Account> _administrativeAccounts() {
    const team = <(String, String, UserRole)>[
      ('Betzabe Escobar', 'betzabxscobar@gmail.com', UserRole.superadmin),
      ('Diego Zurita', 'dandreszurtaf23@gmail.com', UserRole.superadmin),
      ('Alex Yánez', 'alexyanez1119@gmail.com', UserRole.admin),
      ('Mayuri Remache', 'mayuriremache0@gmail.com', UserRole.admin),
      ('Javier Conforme', 'javierconforme18@gmail.com', UserRole.admin),
    ];

    return {
      for (final (index, member) in team.indexed)
        member.$2: _Account(
          password: temporaryAdminPassword,
          user: AppUser(
            id: 'admin-${index + 1}',
            name: member.$1,
            email: member.$2,
            phone: 'ADMIN',
            role: member.$3,
            isVerified: true,
            mustChangePassword: true,
            createdAt: DateTime(2026, 2, 3),
          ),
        ),
    };
  }

  AppUser? _currentUser;
  bool _isLoading = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  /// Inicia sesión.
  ///
  /// Igual que `/api/login` en WEB-RIDE: solo correo y contraseña. El rol no
  /// se elige al entrar, lo define la cuenta y con él la app decide si abre el
  /// home de pasajero, el de conductor o el panel administrativo.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return _run(() async {
      final key = _normalize(email);
      final account = _accounts[key];

      // Mismo mensaje genérico del backend web: no revela si el correo existe.
      if (account == null || account.password != password) {
        throw const AuthException('Correo o contraseña incorrectos.');
      }

      _currentUser = account.user;
      return account.user;
    });
  }

  /// Crea una cuenta nueva.
  ///
  /// Pide los mismos datos que `/api/register`: nombre, correo, teléfono,
  /// contraseña y rol. El vehículo del conductor se registra después, desde su
  /// perfil, para no alargar el formulario de alta.
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
    Vehicle? vehicle,
  }) async {
    return _run(() async {
      final key = _normalize(email);

      // El registro público solo crea pasajeros y conductores, igual que
      // `/api/register`. Las cuentas administrativas las provisiona el equipo.
      if (role.isAdministrative) {
        throw const AuthException(
          'Las cuentas administrativas no se crean desde la app',
        );
      }
      if (_accounts.containsKey(key)) {
        throw const AuthException('Este correo ya tiene una cuenta.');
      }
      final user = AppUser(
        id: 'u-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
        email: key,
        phone: phone.trim(),
        role: role,
        vehicle: vehicle,
        createdAt: DateTime.now(),
      );

      _accounts[key] = _Account(password: password, user: user);
      _currentUser = user;
      return user;
    });
  }

  /// Primer acceso administrativo: reemplaza la contraseña temporal.
  ///
  /// Equivale a `/api/change-password` del backend web.
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
      if (password == temporaryAdminPassword) {
        throw const AuthException(
          'Elige una contraseña distinta a la temporal',
        );
      }

      final account = _accounts[user.email]!;
      final updated = user.copyWith(mustChangePassword: false);
      account
        ..password = password
        ..user = updated;
      _currentUser = updated;
      return updated;
    });
  }

  /// Usuarios visibles para la sesión administrativa activa.
  ///
  /// Igual que `/api/admin/users`: un `admin` no ve a los `superadmin`.
  List<AppUser> visibleUsers() {
    final admin = _currentUser;
    if (admin == null || !admin.role.isAdministrative) {
      throw const AuthException('No tienes permiso para ver este contenido');
    }
    if (admin.mustChangePassword) {
      throw const AuthException('Primero debes cambiar tu contraseña temporal');
    }

    final users = _accounts.values.map((account) => account.user).where(
          (user) => admin.role.isSuperadmin || !user.role.isSuperadmin,
        );

    return users.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
  }

  Future<void> signOut() async {
    _setLoading(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _currentUser = null;
    _setLoading(false);
  }

  /// Cambia el rol activo de la sesión (Modo conductor / Modo pasajero).
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
    final updated = user.copyWith(role: role);
    _currentUser = updated;
    _accounts[user.email]?.user = updated;
    notifyListeners();
  }

  Future<AppUser> _run(Future<AppUser> Function() action) async {
    _setLoading(true);
    try {
      await Future<void>.delayed(_latency);
      final user = await action();
      return user;
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
}
