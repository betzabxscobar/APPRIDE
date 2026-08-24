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
/// Simula la latencia de un backend para que las pantallas ya manejen estados
/// de carga y error. Cuando exista la API real solo hay que reemplazar el
/// cuerpo de [signIn], [register] y [signOut]: la interfaz pública no cambia.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const Duration _latency = Duration(milliseconds: 900);

  final Map<String, _Account> _accounts = {
    'pasajero@ride.app': _Account(
      password: 'Ride1234',
      user: const AppUser(
        id: 'demo-passenger',
        name: 'Andrea Salazar',
        email: 'pasajero@ride.app',
        phone: '0991234567',
        role: UserRole.passenger,
        isVerified: true,
      ),
    ),
    'conductor@ride.app': _Account(
      password: 'Ride1234',
      user: const AppUser(
        id: 'demo-driver',
        name: 'Carlos Andrade',
        email: 'conductor@ride.app',
        phone: '0987654321',
        role: UserRole.driver,
        isVerified: true,
        vehicle: Vehicle(model: 'Toyota Corolla', plate: 'PDC-1234', year: 2021),
      ),
    ),
  };

  AppUser? _currentUser;
  bool _isLoading = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  /// Inicia sesión.
  ///
  /// Si se envía [expectedRole] se valida que la cuenta tenga ese rol, para
  /// que quien eligió "Conduzco" no entre por error a la vista de pasajero.
  Future<AppUser> signIn({
    required String email,
    required String password,
    UserRole? expectedRole,
  }) async {
    return _run(() async {
      final key = _normalize(email);
      final account = _accounts[key];

      if (account == null) {
        throw const AuthException('No encontramos una cuenta con ese correo');
      }
      if (account.password != password) {
        throw const AuthException('La contraseña no es correcta');
      }
      if (expectedRole != null && account.user.role != expectedRole) {
        throw AuthException(
          'Esta cuenta está registrada como ${account.user.role.displayName}. '
          'Cambia de opción para continuar.',
        );
      }

      _currentUser = account.user;
      return account.user;
    });
  }

  /// Crea una cuenta nueva. [vehicle] es obligatorio si [role] es conductor.
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

      if (_accounts.containsKey(key)) {
        throw const AuthException('Ya existe una cuenta con ese correo');
      }
      if (role.isDriver && vehicle == null) {
        throw const AuthException('Registra los datos de tu vehículo');
      }

      final user = AppUser(
        id: 'u-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
        email: key,
        phone: phone.trim(),
        role: role,
        vehicle: vehicle,
      );

      _accounts[key] = _Account(password: password, user: user);
      _currentUser = user;
      return user;
    });
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
