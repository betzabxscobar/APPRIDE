import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/app_user.dart';
import 'push_service.dart';
import 'trip_session_store.dart';
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

  /// Mínimo para una cuenta normal. El mismo que exige `/api/register` en
  /// WEB-RIDE y el que valida `Validators.password`.
  static const int passwordMinLength = 8;

  static const String _profileColumns =
      'id, email, full_name, phone, role, foto_url, must_change_password, '
      'created_at';

  /// Bucket público de las fotos de perfil.
  ///
  /// Público a propósito: una foto de perfil la ve la otra parte del viaje, y
  /// firmar una URL nueva cada vez que se pinta un avatar sería una llamada de
  /// red por cada tarjeta de la lista. Los documentos, que sí son sensibles,
  /// viven en `documentos`, que es privado.
  static const String _bucketAvatares = 'avatares';

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
    } on sb.AuthException {
      // El token ya no vale: esta sesión está muerta de verdad.
      await _signOutLocal();
    } on sb.PostgrestException catch (error) {
      // Postgres contestó y dijo que no. Si el perfil no existe, la sesión no
      // sirve; cualquier otra cosa es un problema del servidor y no es motivo
      // para echar a nadie.
      if (error.code == 'PGRST116') {
        await _signOutLocal();
      }
    } catch (_) {
      // Sin red, DNS caído, tiempo agotado.
      //
      // Antes esto cerraba la sesión: abrir la app en el ascensor te dejaba
      // fuera y con la contraseña por delante. La sesión sigue siendo válida;
      // lo que falta es conexión. Se deja como está y se reintenta al volver.
    } finally {
      _setLoading(false);
    }

    _client.auth.onAuthStateChange.listen((state) async {
      if (state.event == sb.AuthChangeEvent.signedOut) {
        await _olvidarSesion();
        notifyListeners();
        return;
      }

      // Sesión que aparece sin que nadie la haya pedido por aquí: es el enlace
      // del correo abriendo la app (`ride://login-callback`). Supabase ya
      // canjeó el código, pero el perfil no lo había leído nadie, así que la
      // app se quedaba en la pantalla de entrar teniendo la sesión hecha.
      //
      // La condición del perfil vacío importa: al entrar con correo y
      // contraseña, `signIn` ya lo cargó y no hay que volver a pedirlo.
      if (state.event == sb.AuthChangeEvent.passwordRecovery) {
        _recuperandoContrasena = true;
        notifyListeners();
      }

      final entra = state.event == sb.AuthChangeEvent.signedIn ||
          state.event == sb.AuthChangeEvent.passwordRecovery;

      if (entra && state.session != null && _currentUser == null) {
        try {
          _currentUser = await _loadProfile();
          notifyListeners();
        } catch (_) {
          // Sin red se queda como estaba. La sesión sigue guardada y el
          // siguiente arranque la recupera.
        }
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
          emailRedirectTo: enlaceDeVuelta,
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

  /// A dónde vuelve el correo de confirmación y el de contraseña olvidada.
  ///
  /// Sin esto Supabase usa la «Site URL» del proyecto, que apunta al servidor
  /// de desarrollo de la web (`localhost:5173`). En un teléfono eso no existe:
  /// el enlace del correo abría el navegador y moría en «No se puede acceder a
  /// este sitio».
  ///
  /// El mismo esquema está declarado en `AndroidManifest.xml` y tiene que
  /// estar dado de alta en Supabase, en Authentication → URL Configuration →
  /// Redirect URLs. Si falta allí, Supabase lo ignora y vuelve a mandar a la
  /// Site URL.
  static const String enlaceDeVuelta = 'ride://login-callback';

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

  /// Convierte una cuenta de pasajero en cuenta de chofer.
  ///
  /// No crea una cuenta nueva: es la misma, con su correo, su teléfono y su
  /// historial. Eso importa porque `profiles` tiene el teléfono con índice
  /// único, así que abrir otra cuenta obligaba a inventarse un número.
  ///
  /// **No le da ningún permiso.** Entra en `conductores` como 'pendiente' y no
  /// puede aprobarse solo: hasta que administración revise sus papeles no
  /// puede conectarse ni recibir solicitudes. Lo único que cambia de
  /// inmediato es la pantalla que ve y el poder subir sus documentos.
  ///
  /// La base lo rechaza si tiene un viaje pedido o en marcha: cambiarle la
  /// pantalla debajo de los pies dejaría ese viaje huérfano.
  Future<AppUser> convertirmeEnChofer() async {
    return _run(() async {
      await _client.rpc('quiero_ser_chofer');
      // El rol lo decide el servidor, así que el perfil se vuelve a leer en
      // vez de darlo por cambiado aquí.
      final user = await _loadProfile();
      _currentUser = user;
      _activeView = null;
      notifyListeners();
      return user;
    });
  }

  /// Pone la contraseña nueva de quien llegó por el enlace de recuperación.
  ///
  /// A diferencia de [cambiarContrasena], aquí **no** se pide la actual: quien
  /// entra por este camino no la sabe, que es justamente el motivo. Lo que
  /// autoriza el cambio es la sesión que creó el enlace del correo.
  Future<void> establecerContrasenaNueva(String password) async {
    if (_client.auth.currentSession == null) {
      throw const AuthException(
        'El enlace caducó. Pide otro correo para restablecerla.',
      );
    }
    if (password.length < passwordMinLength) {
      throw const AuthException(
        'Usa al menos $passwordMinLength caracteres',
      );
    }

    _setLoading(true);
    try {
      try {
        await _client.auth.updateUser(sb.UserAttributes(password: password));
      } on sb.AuthException catch (error) {
        throw AuthException(_translate(error.message));
      }

      _recuperandoContrasena = false;

      // El perfil puede no estar cargado: al abrir la app desde el enlace, la
      // sesión llega antes de que nadie haya leído `profiles`.
      _currentUser ??= await _loadProfile();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Pide el correo con el enlace para restablecer la contraseña.
  ///
  /// No revela si el correo existe: Supabase responde igual en ambos casos y
  /// la pantalla muestra siempre el mismo aviso, para no filtrar qué cuentas
  /// hay registradas.
  ///
  /// El enlace usa `ride://login-callback`, registrado en Android e iOS, para
  /// devolver al usuario a la aplicación y completar el cambio allí.
  Future<void> requestPasswordReset(String email) async {
    _setLoading(true);
    try {
      await _client.auth.resetPasswordForEmail(
        _normalize(email),
        redirectTo: enlaceDeVuelta,
      );
    } on sb.AuthException catch (error) {
      throw AuthException(_translate(error.message));
    } finally {
      _setLoading(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Mi cuenta
  //
  // Todo lo de aquí lo hace la persona sobre su propio perfil. El rol no
  // aparece por ningún lado a propósito: el trigger `prevent_role_self_edit()`
  // rechaza cualquier intento de cambiárselo uno mismo, así que ofrecerlo
  // sería ofrecer un botón que siempre falla.
  // ---------------------------------------------------------------------------

  /// Vuelve a leer el perfil de la base y avisa a las pantallas.
  ///
  /// Se usa después de cambiar algo y al volver de una pantalla que pudo
  /// tocarlo. Si no hay sesión no hace nada.
  Future<AppUser?> refrescarPerfil() async {
    if (_client.auth.currentSession == null) return null;
    try {
      _currentUser = await _loadProfile();
      notifyListeners();
    } on AuthException {
      // Sin red se conserva el perfil que ya había: es preferible a vaciar la
      // pantalla.
    }
    return _currentUser;
  }

  /// Cambia el nombre y el teléfono.
  ///
  /// El teléfono no es un adorno: es lo que ve la otra parte del viaje en
  /// `viajes_detalle` para poder llamarse.
  Future<AppUser> actualizarDatos({
    required String nombre,
    required String telefono,
  }) async {
    return _run(() async {
      final user = _currentUser;
      if (user == null) throw const AuthException('Debes iniciar sesión');

      final nombreLimpio = nombre.trim();
      final telefonoLimpio = telefono.trim();
      if (nombreLimpio.length < 3) {
        throw const AuthException('Ingresa tu nombre completo');
      }

      try {
        await _client.from('profiles').update({
          'full_name': nombreLimpio,
          'phone': telefonoLimpio.isEmpty ? null : telefonoLimpio,
        }).eq('id', user.id);
      } on sb.PostgrestException catch (error) {
        throw AuthException(_translate(error.message));
      }

      final actualizado = await _loadProfile();
      _currentUser = actualizado;
      return actualizado;
    });
  }

  /// Sube la foto de perfil y la deja guardada en `profiles.foto_url`.
  ///
  /// La ruta empieza por el id del usuario (`<uid>/perfil.jpg`) porque las
  /// políticas de Storage comparan ese primer segmento con `auth.uid()`: es lo
  /// que impide escribir en la carpeta de otro.
  ///
  /// `upsert` reemplaza la anterior en vez de acumular archivos, y por eso la
  /// URL guardada lleva un `?v=` con la marca de tiempo: la ruta no cambia y
  /// sin ese parámetro el teléfono seguiría enseñando la foto vieja.
  Future<AppUser> cambiarFoto(File archivo) async {
    return _run(() async {
      final user = _currentUser;
      if (user == null) throw const AuthException('Debes iniciar sesión');

      final ruta = '${user.id}/perfil.jpg';
      try {
        await _client.storage.from(_bucketAvatares).upload(
              ruta,
              archivo,
              fileOptions: const sb.FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } on sb.StorageException catch (error) {
        throw AuthException(_traducirStorage(error.message));
      }

      final url = _client.storage.from(_bucketAvatares).getPublicUrl(ruta);
      final version = DateTime.now().millisecondsSinceEpoch;

      try {
        await _client
            .from('profiles')
            .update({'foto_url': '$url?v=$version'}).eq('id', user.id);
      } on sb.PostgrestException {
        throw const AuthException('Subimos la foto pero no pudimos guardarla');
      }

      final actualizado = await _loadProfile();
      _currentUser = actualizado;
      return actualizado;
    });
  }

  /// Quita la foto y vuelve a las iniciales.
  Future<AppUser> quitarFoto() async {
    return _run(() async {
      final user = _currentUser;
      if (user == null) throw const AuthException('Debes iniciar sesión');

      try {
        await _client.storage
            .from(_bucketAvatares)
            .remove(['${user.id}/perfil.jpg']);
      } on sb.StorageException {
        // Si el archivo ya no estaba, da igual: lo que importa es dejar el
        // perfil sin foto.
      }

      try {
        await _client
            .from('profiles')
            .update({'foto_url': null}).eq('id', user.id);
      } on sb.PostgrestException {
        throw const AuthException('No pudimos quitar tu foto');
      }

      final actualizado = await _loadProfile();
      _currentUser = actualizado;
      return actualizado;
    });
  }

  /// Pide el cambio de correo.
  ///
  /// Se comprueba antes la contraseña actual volviendo a iniciar sesión: sin
  /// eso, un teléfono desbloqueado y prestado un minuto basta para llevarse la
  /// cuenta a otro correo.
  ///
  /// El correo **no cambia al volver de aquí**. Supabase manda un enlace de
  /// confirmación —a la dirección nueva, y también a la vieja si el proyecto
  /// tiene activada la confirmación doble— y solo entonces se hace efectivo.
  /// El trigger `on_auth_user_email_changed` es el que copia el correo nuevo a
  /// `public.profiles` en ese momento.
  Future<void> cambiarCorreo({
    required String nuevoCorreo,
    required String contrasena,
  }) async {
    _setLoading(true);
    try {
      final user = _currentUser;
      if (user == null) throw const AuthException('Debes iniciar sesión');

      final correo = _normalize(nuevoCorreo);
      if (correo == _normalize(user.email)) {
        throw const AuthException('Ese ya es tu correo actual');
      }

      await _reautenticar(contrasena);

      try {
        await _client.auth.updateUser(sb.UserAttributes(email: correo));
      } on sb.AuthException catch (error) {
        throw AuthException(_translate(error.message));
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Cambia la contraseña.
  ///
  /// Igual que el correo: primero se comprueba la actual. Supabase deja
  /// cambiarla solo con la sesión abierta, y esa comodidad es justo el agujero
  /// que se cierra aquí.
  Future<void> cambiarContrasena({
    required String actual,
    required String nueva,
  }) async {
    _setLoading(true);
    try {
      final user = _currentUser;
      if (user == null) throw const AuthException('Debes iniciar sesión');

      // Las cuentas administrativas tienen su propio mínimo, más largo.
      final minimo =
          user.role.isAdministrative ? adminPasswordMinLength : passwordMinLength;
      if (nueva.length < minimo) {
        throw AuthException(
          'La contraseña debe tener mínimo $minimo caracteres',
        );
      }
      if (nueva == actual) {
        throw const AuthException('Elige una contraseña distinta a la actual');
      }

      await _reautenticar(actual);

      try {
        await _client.auth.updateUser(sb.UserAttributes(password: nueva));
      } on sb.AuthException catch (error) {
        throw AuthException(_translate(error.message));
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Comprueba que quien está delante del teléfono sabe la contraseña.
  ///
  /// Se hace con `signInWithPassword` sobre el mismo correo: si la contraseña
  /// es correcta simplemente se renueva la sesión que ya había, y si no lo es
  /// Supabase responde con credenciales inválidas y la sesión abierta sigue
  /// intacta.
  Future<void> _reautenticar(String contrasena) async {
    final user = _currentUser;
    if (user == null) throw const AuthException('Debes iniciar sesión');
    if (contrasena.isEmpty) {
      throw const AuthException('Ingresa tu contraseña actual');
    }

    try {
      await _client.auth.signInWithPassword(
        email: _normalize(user.email),
        password: contrasena,
      );
    } on sb.AuthException catch (error) {
      final normalizado = error.message.toLowerCase();
      if (normalizado.contains('invalid login credentials')) {
        throw const AuthException('Tu contraseña actual no es correcta.');
      }
      throw AuthException(_translate(error.message));
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
      await _olvidarSesion();
      _setLoading(false);
    }
  }

  /// Cierre local, sin llamar al servidor. Para cuando el token ya no vale.
  Future<void> _signOutLocal() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Da igual que falle: lo que importa es no dejar datos en el teléfono.
    }
    await _olvidarSesion();
  }

  /// Borra todo rastro de la cuenta que se va.
  ///
  /// El viaje guardado en disco incluido: si se queda, la siguiente cuenta que
  /// entre en este teléfono vería el viaje de la anterior mientras carga.
  Future<void> _olvidarSesion() async {
    _currentUser = null;
    _activeView = null;
    _recuperandoContrasena = false;
    await TripSessionStore.instance.limpiar();
  }

  // ---------------------------------------------------------------------------
  // Vista activa
  //
  // El rol real de la cuenta (`currentUser.role`) sale de `public.profiles` y
  // NUNCA se toca aquí: el trigger `prevent_role_self_edit()` impide que nadie
  // se cambie el rol a sí mismo, y las políticas RLS resuelven los permisos con
  // `current_user_role()`, que lee esa tabla.
  //
  // Lo que cambia es solo qué pantalla se muestra. Un admin que abre la vista
  // de pasajero sigue siendo admin para la base de datos; ve la interfaz con
  // sus propios datos, no con los de otra persona.
  // ---------------------------------------------------------------------------

  /// La sesión entró por un enlace de «olvidé mi contraseña».
  ///
  /// Mientras esté puesta, la app enseña la pantalla de poner clave nueva y
  /// nada más. A quien llega por aquí no se le puede dejar pasar sin más:
  /// entró sin escribir ninguna contraseña, así que hasta que ponga una la
  /// cuenta sigue abierta para cualquiera que tenga ese correo delante.
  bool _recuperandoContrasena = false;
  bool get recuperandoContrasena => _recuperandoContrasena;

  UserRole? _activeView;

  /// Pantalla que se está mostrando. Por defecto, la que corresponde al rol.
  UserRole get activeView => _activeView ?? _currentUser?.role ?? UserRole.passenger;

  /// `true` cuando se está viendo una pantalla distinta a la del rol real.
  bool get isViewingOtherPanel {
    final user = _currentUser;
    return user != null && _activeView != null && _activeView != user.role;
  }

  /// Vistas a las que puede entrar la sesión actual, en orden de presentación.
  ///
  /// - `superadmin`: su panel, el panel visto como admin, pasajero y conductor.
  /// - `admin`: su panel, pasajero y conductor. Nunca la vista de superadmin.
  /// - `driver`: conductor y pasajero.
  /// - `passenger`: pasajero, y conductor solo si ya registró un vehículo.
  List<UserRole> get availableViews {
    final user = _currentUser;
    if (user == null) return const [];

    return user.role.viewsAllowed();
  }

  /// Cambia la pantalla activa dentro de lo que permite el rol real.
  void switchView(UserRole view) {
    final user = _currentUser;
    if (user == null || activeView == view) return;

    if (!availableViews.contains(view)) {
      // El caso que más importa: un admin no puede abrir la vista de
      // superadmin. La comprobación es genérica para no dejar huecos.
      throw AuthException(
        view.isAdministrative
            ? 'Tu cuenta no tiene acceso a ese panel'
            : 'No puedes abrir esa vista',
      );
    }

    // Aqui vivia una comprobacion de vehiculo que ya no puede llegar: la vista
    // de chofer solo esta en la lista de `driver`, `admin` y `superadmin`, y a
    // ninguno de los tres se le exige. A un chofer menos que a nadie, que su
    // pantalla es donde registra el vehiculo: exigirselo dejaba atrapado en la
    // vista de pasajero a quien acababa de pasarse a chofer.

    _activeView = view == user.role ? null : view;
    notifyListeners();
  }

  /// Vuelve a la pantalla que corresponde al rol real de la cuenta.
  void resetView() {
    if (_activeView == null) return;
    _activeView = null;
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
      fotoUrl: row['foto_url'] as String?,
      isVerified: true,
      mustChangePassword: (row['must_change_password'] as bool?) ?? false,
      createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    );
  }

  /// A quién se le están escuchando los avisos ahora mismo.
  String? _avisandoA;

  /// Engancha y desengancha los avisos del teléfono según quién tenga la
  /// sesión.
  ///
  /// Va aquí, colgado de `notifyListeners`, y no repartido por los once sitios
  /// donde se asigna el usuario: uno de esos sitios se olvida tarde o temprano
  /// y el chofer se queda sin avisos sin que nadie sepa por qué.
  void _sincronizarAvisos() {
    final id = _currentUser?.id;
    if (id == _avisandoA) return;
    _avisandoA = id;

    if (id == null) {
      unawaited(PushService.instance.dejarDeEscuchar());
    } else {
      // Sin `await`: que el aviso tarde en engancharse no puede frenar la
      // pantalla, y si falla se reintenta al siguiente cambio de sesión.
      unawaited(PushService.instance.escuchar(id));
    }
  }

  @override
  void notifyListeners() {
    _sincronizarAvisos();
    super.notifyListeners();
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
      // Supabase no dice QUE fallo dentro del trigger, asi que aqui no se
      // puede afirmar cual de los dos es. Antes esto decia «este correo no
      // puede registrarse con ese rol» y mandaba a cambiar el correo cuando
      // casi siempre el choque era del telefono: `profiles` lo tiene con
      // indice unico, y una cuenta de pasajero ya lo estaba usando.
      return 'Ese correo o ese teléfono ya están registrados. '
          'El teléfono solo puede estar en una cuenta.';
    }
    if (normalized.contains('a user with this email address has already')) {
      return 'Ese correo ya está en uso por otra cuenta.';
    }
    // `profiles.phone` y `profiles.email` son únicos en la base. Sin esto, el
    // texto crudo de Postgres —«duplicate key value violates unique
    // constraint...»— acababa en la pantalla del usuario.
    if (normalized.contains('profiles_phone_key')) {
      return 'Ese teléfono ya está registrado en otra cuenta.';
    }
    if (normalized.contains('profiles_email_key')) {
      return 'Ese correo ya está registrado en otra cuenta.';
    }
    if (normalized.contains('duplicate key value')) {
      return 'Esos datos ya están registrados en otra cuenta.';
    }
    if (normalized.contains('new password should be different')) {
      return 'Elige una contraseña distinta a la actual.';
    }
    return message;
  }

  /// Los errores de Storage llegan en inglés y con jerga de bucket.
  String _traducirStorage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('exceeded the maximum allowed size') ||
        normalized.contains('too large')) {
      return 'La foto pesa más de 2 MB. Usa una más liviana.';
    }
    if (normalized.contains('mime type') || normalized.contains('not allowed')) {
      return 'Formato no admitido. Sube una imagen JPG, PNG o WebP.';
    }
    // Este caso costo encontrarlo: el bucket `avatares` tenia politicas de
    // escritura pero no de lectura, y `upsert` acaba en un
    // `INSERT ... ON CONFLICT DO UPDATE ... RETURNING *` que necesita leer la
    // fila que devuelve. Ya esta arreglado en la base; el mensaje se queda
    // para que un fallo de permisos no vuelva a esconderse detras de un
    // «intentalo de nuevo».
    if (normalized.contains('row-level security') ||
        normalized.contains('unauthorized') ||
        normalized.contains('access denied')) {
      return 'No tienes permiso para guardar tu foto. Avisa al equipo.';
    }
    return 'No pudimos subir la foto. Inténtalo de nuevo.';
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
