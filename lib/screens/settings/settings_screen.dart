import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../core/theme_controller.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/panel_switcher.dart';
import '../../widgets/ride_card.dart';
import '../../widgets/user_avatar.dart';
import '../driver/driver_profile_screen.dart';
import '../notifications/notifications_screen.dart';
import '../payments/payment_methods_screen.dart';
import '../support/support_screen.dart';
import 'account_forms.dart';

/// Configuración: todo lo que una persona puede cambiar de su propia cuenta.
///
/// Hasta ahora no existía. Lo poco que había —el cambio de panel y cerrar
/// sesión— vivía en la hoja de cuenta, y cosas como la foto, el correo o la
/// contraseña no se podían tocar desde la app aunque la base ya las
/// soportara: `profiles.foto_url` y el bucket `avatares` llevaban ahí desde el
/// principio sin que nada los usara.
///
/// El rol no aparece por ningún lado y no es un olvido: el trigger
/// `prevent_role_self_edit()` impide que nadie se cambie el rol a sí mismo.
/// Lo que sí se puede es cambiar de **vista**, que es otra cosa y ya tiene su
/// sitio en [PanelSwitcher].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _subiendoFoto = false;
  String? _error;

  AppUser? get _user => AuthService.instance.currentUser;

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pantalla),
    );
    // Al volver puede haber cambiado el perfil: se relee para que la cabecera
    // no se quede con el nombre viejo.
    await AuthService.instance.refrescarPerfil();
  }

  /// Cambia la foto de perfil.
  ///
  /// La imagen se reduce antes de subir: una foto de 12 MP pasaría del límite
  /// de 2 MB del bucket, y para un avatar de 60 px no aporta nada.
  Future<void> _cambiarFoto(ImageSource origen) async {
    setState(() {
      _subiendoFoto = true;
      _error = null;
    });
    try {
      final foto = await ImagePicker().pickImage(
        source: origen,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 82,
      );
      if (foto == null) return;

      await AuthService.instance.cambiarFoto(File(foto.path));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cambiar tu foto.');
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _quitarFoto() async {
    setState(() {
      _subiendoFoto = true;
      _error = null;
    });
    try {
      await AuthService.instance.quitarFoto();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _elegirOrigenFoto(AppUser user) async {
    final origen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            if (user.fotoUrl != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.ride.danger,
                ),
                title: Text(
                  'Quitar foto',
                  style: TextStyle(color: context.ride.danger),
                ),
                onTap: () => Navigator.of(context).pop('quitar'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (origen is ImageSource) {
      await _cambiarFoto(origen);
    } else if (origen == 'quitar') {
      await _quitarFoto();
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a entrar con tu correo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.ride.danger),
            child: const Text('Sí, salir'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    await AuthService.instance.signOut();
    // La raíz reacciona al cierre de sesión y vuelve al acceso; esta pantalla
    // se cierra sola para no quedar encima.
    if (mounted) Navigator.of(context).popUntil((ruta) => ruta.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // Escucha a los dos: el perfil cambia con AuthService y el tema con
    // ThemeController, y las dos cosas se ven en esta pantalla.
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthService.instance,
        ThemeController.instance,
      ]),
      builder: (context, _) {
        final user = _user;
        if (user == null) {
          return const Scaffold(
            body: Center(child: Text('Tu sesión se cerró.')),
          );
        }
        return _contenido(context, user);
      },
    );
  }

  Widget _contenido(BuildContext context, AppUser user) {
    final ride = context.ride;
    final esConductor =
        user.role.isDriver || AuthService.instance.activeView.isDriver;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Cabecera(
            user: user,
            subiendo: _subiendoFoto,
            onTocarFoto: () => _elegirOrigenFoto(user),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 26),

          const _Titulo('Apariencia'),
          const SizedBox(height: 10),
          const _SelectorTema(),

          const SizedBox(height: 26),
          const _Titulo('Mi cuenta'),
          const SizedBox(height: 10),
          _Opcion(
            icono: Icons.person_outline,
            titulo: 'Datos personales',
            detalle: user.phone.isEmpty
                ? 'Falta tu teléfono'
                : '${user.name} · ${user.phone}',
            resaltado: user.phone.isEmpty,
            onTap: () => _abrir(EditarDatosScreen(user: user)),
          ),
          _Opcion(
            icono: Icons.alternate_email,
            titulo: 'Correo',
            detalle: user.email,
            onTap: () => _abrir(CambiarCorreoScreen(user: user)),
          ),
          _Opcion(
            icono: Icons.lock_outline,
            titulo: 'Contraseña',
            detalle: 'Cámbiala cuando quieras',
            onTap: () => _abrir(CambiarContrasenaScreen(user: user)),
          ),

          if (esConductor) ...[
            const SizedBox(height: 26),
            const _Titulo('Conductor'),
            const SizedBox(height: 10),
            _Opcion(
              icono: Icons.badge_outlined,
              titulo: 'Vehículo y documentos',
              detalle: 'Cédula, licencia, SOAT, matrícula y tus autos',
              onTap: () => _abrir(const DriverProfileScreen()),
            ),
          ],

          const SizedBox(height: 26),
          const _Titulo('Aplicación'),
          const SizedBox(height: 10),
          _Opcion(
            icono: Icons.notifications_none,
            titulo: 'Notificaciones',
            detalle: 'Avisos de tus viajes y de tu cuenta',
            onTap: () => _abrir(const NotificationsScreen()),
          ),
          if (!user.role.isAdministrative)
            _Opcion(
              icono: Icons.payments_outlined,
              titulo: 'Métodos de pago',
              detalle: 'Efectivo y tarjetas guardadas',
              onTap: () => _abrir(const PaymentMethodsScreen()),
            ),
          // Para pasajeros y para choferes: hasta ahora ninguno de los dos
          // tenía a quién escribirle si algo salía mal.
          _Opcion(
            icono: Icons.support_agent,
            titulo: 'Soporte',
            detalle: 'Cuéntanos si algo salió mal',
            onTap: () => _abrir(const SupportScreen()),
          ),

          // El bloque entero solo aparece si de verdad hay a dónde cambiar.
          // `PanelSwitcher` se esconde solo cuando hay una sola vista, y sin
          // esta condición el título y su explicación quedarían encima de un
          // hueco vacío: le pasa a cualquier pasajero y a cualquier admin.
          if (AuthService.instance.availableViews.length > 1) ...[
            const SizedBox(height: 26),
            const _Titulo('Vista'),
            const SizedBox(height: 4),
            Text(
              'Cambia la pantalla que ves. Tu rol y tus permisos no cambian.',
              style: TextStyle(fontSize: AppText.label, color: ride.inkMuted),
            ),
            const SizedBox(height: 12),
            PanelSwitcher(onSwitched: () => Navigator.of(context).pop()),
          ],

          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: _cerrarSesion,
            icon: Icon(Icons.logout, size: 20, color: ride.danger),
            label: Text(
              'Cerrar sesión',
              style: TextStyle(color: ride.danger),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: ride.danger.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto, nombre, correo y rol.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.user,
    required this.subiendo,
    required this.onTocarFoto,
  });

  final AppUser user;
  final bool subiendo;
  final VoidCallback onTocarFoto;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;

    return RideCard(
      child: Row(
        children: [
          Stack(
            children: [
              UserAvatar(
                iniciales: user.initials,
                fotoUrl: user.fotoUrl,
                radio: 34,
                color: user.role.accent,
              ),
              if (subiendo)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ride.surface.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                ),
              // El lápiz va sobre la foto porque es donde la gente lo busca.
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: ride.accent,
                  shape: CircleBorder(
                    side: BorderSide(color: ride.surface, width: 2.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: subiendo ? null : onTocarFoto,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 15,
                        color: ride.isDark ? const Color(0xFF04121C) : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    fontSize: AppText.h3,
                    fontWeight: FontWeight.w800,
                    color: ride.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.label,
                    color: ride.inkMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ride.isDark
                        ? user.role.accent.withValues(alpha: 0.18)
                        : user.role.accentSoft,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    user.role.displayName,
                    style: TextStyle(
                      fontSize: AppText.micro,
                      fontWeight: FontWeight.w800,
                      color: user.role.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Claro, oscuro o el del sistema.
///
/// Las tres van a la vista en vez de esconderse en un desplegable: son tres
/// opciones y la persona quiere ver cuál está activa sin abrir nada.
class _SelectorTema extends StatelessWidget {
  const _SelectorTema();

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final actual = ThemeController.instance.mode;

    return RideCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final modo in ThemeMode.values)
            InkWell(
              onTap: () => ThemeController.instance.cambiar(modo),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      ThemeController.icono(modo),
                      size: 22,
                      color: modo == actual ? ride.accent : ride.inkMuted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ThemeController.etiqueta(modo),
                            style: TextStyle(
                              fontSize: AppText.small,
                              fontWeight: FontWeight.w700,
                              color: ride.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ThemeController.detalle(modo),
                            style: TextStyle(
                              fontSize: AppText.micro,
                              color: ride.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Un check en vez de un radio: la fila entera ya es el
                    // área de toque, y un radio de 20 px al lado invita a
                    // apuntarle al radio y fallar.
                    Icon(
                      modo == actual
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: modo == actual ? ride.accent : ride.borderStrong,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: AppText.micro,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: context.ride.inkMuted,
      ),
    );
  }
}

/// Una fila de la lista de ajustes.
class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.resaltado = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  /// Marca en ámbar lo que le falta a la cuenta, como un teléfono sin poner.
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final tinta = resaltado ? ride.danger : ride.inkMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RideCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icono, size: 22, color: resaltado ? ride.danger : ride.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: AppText.small,
                      fontWeight: FontWeight.w700,
                      color: ride.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppText.micro, color: tinta),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 22, color: ride.inkFaint),
          ],
        ),
      ),
    );
  }
}
