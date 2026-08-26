import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../widgets/panel_switcher.dart';

/// Secciones del panel, las mismas de la barra lateral de WEB-RIDE.
enum _Section {
  resumen('Resumen', Icons.dashboard_outlined),
  usuarios('Usuarios', Icons.people_outline),
  conductores('Conductores', Icons.drive_eta_outlined),
  viajes('Viajes', Icons.route_outlined),
  tarifas('Tarifas', Icons.payments_outlined),
  soporte('Soporte', Icons.help_outline);

  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Panel administrativo. Versión móvil del `AdminDashboard` de WEB-RIDE:
/// mismas métricas, mismo listado de cuentas y las mismas reglas de
/// visibilidad entre `admin` y `superadmin`.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.user,
    required this.viewAs,
  });

  final AppUser user;

  /// Panel que se está mostrando: `admin` o `superadmin`.
  ///
  /// Un superadmin puede abrir el panel *visto como admin* para revisar qué
  /// alcance tiene ese rol. Su cuenta sigue siendo superadmin — esto solo
  /// cambia lo que se presenta.
  final UserRole viewAs;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _Section _section = _Section.resumen;
  List<AppUser> _users = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  bool _loadingUsers = true;

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await AuthService.instance.visibleUsers();
      if (!mounted) return;
      setState(() {
        // Al mirar el panel *como admin*, RLS sigue enviando a los superadmin
        // porque el rol real de la cuenta no cambió. Se ocultan aquí para que
        // la previsualización sea fiel a lo que vería un admin de verdad.
        //
        // Es filtrado de presentación, no de seguridad: la barrera real son
        // las políticas RLS, que sí aplican para una cuenta admin auténtica.
        _users = widget.viewAs.isSuperadmin
            ? users
            : users.where((u) => !u.role.isSuperadmin).toList();
        _error = null;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  /// Manda la vista, no el rol: si un superadmin abrió el panel como admin,
  /// la pantalla se comporta como la de un admin.
  bool get _isSuperadmin => widget.viewAs.isSuperadmin;
  String get _accessName =>
      _isSuperadmin ? 'SUPERADMINISTRACIÓN' : 'ADMINISTRACIÓN';

  int _countOf(UserRole role) =>
      _users.where((user) => user.role == role).length;

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              _accessName,
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.purple,
              ),
            ),
            Text(_section.label),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.purpleSoft,
              child: Text(
                widget.user.initials,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _AdminDrawer(
        user: widget.user,
        accessName: _accessName,
        showPanelSwitcher: true,
        active: _section,
        onSelect: (section) {
          Navigator.of(context).pop();
          setState(() => _section = section);
        },
        onSignOut: _signOut,
      ),
      body: SafeArea(
        child: switch (_section) {
          _Section.resumen => _Overview(
              user: widget.user,
              users: _users,
              error: _error,
              loading: _loadingUsers,
              passengers: _countOf(UserRole.passenger),
              drivers: _countOf(UserRole.driver),
              administrators: _countOf(UserRole.admin) +
                  _countOf(UserRole.superadmin),
              onSeeAll: () => setState(() => _section = _Section.usuarios),
            ),
          _Section.usuarios =>
            _UserList(users: _users, error: _error, loading: _loadingUsers),
          _ => _Placeholder(
              section: _section,
              onBack: () => setState(() => _section = _Section.resumen),
            ),
        },
      ),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({
    required this.user,
    required this.accessName,
    required this.showPanelSwitcher,
    required this.active,
    required this.onSelect,
    required this.onSignOut,
  });

  final AppUser user;
  final String accessName;
  final bool showPanelSwitcher;
  final _Section active;
  final ValueChanged<_Section> onSelect;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'R',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ride',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          accessName,
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final section in _Section.values)
                    ListTile(
                      leading: Icon(
                        section.icon,
                        size: 21,
                        color: section == active
                            ? AppColors.purple
                            : AppColors.inkMuted,
                      ),
                      title: Text(
                        section.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: section == active
                              ? AppColors.ink
                              : AppColors.inkMuted,
                        ),
                      ),
                      selected: section == active,
                      selectedTileColor: AppColors.purpleSoft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      onTap: () => onSelect(section),
                    ),
                ],
              ),
            ),
            if (showPanelSwitcher) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: PanelSwitcher(
                  onSwitched: () => Navigator.of(context).pop(),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppColors.green,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sistema operativo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            'Acceso protegido',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Cerrar sesión'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.user,
    required this.users,
    required this.error,
    required this.loading,
    required this.passengers,
    required this.drivers,
    required this.administrators,
    required this.onSeeAll,
  });

  final AppUser user;
  final List<AppUser> users;
  final String? error;
  final bool loading;
  final int passengers;
  final int drivers;
  final int administrators;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.purpleSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PANEL DE CONTROL',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hola, ${user.firstName}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Revisa el estado real de las cuentas registradas en Ride.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: AppColors.purple,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sesión ${user.role.displayName.toLowerCase()} segura',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Pasajeros',
                value: passengers,
                color: AppColors.primary,
                background: AppColors.primarySoft,
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Conductores',
                value: drivers,
                color: AppColors.green,
                background: AppColors.greenSoft,
                icon: Icons.drive_eta_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Equipo administrativo',
                value: administrators,
                color: AppColors.purple,
                background: AppColors.purpleSoft,
                icon: Icons.shield_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Viajes registrados',
                value: 0,
                color: AppColors.danger,
                background: Color(0x14E5484D),
                icon: Icons.route_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Card(
          title: 'Usuarios registrados',
          subtitle: 'Información obtenida desde Supabase.',
          action: TextButton(onPressed: onSeeAll, child: const Text('Ver todos')),
          child: Column(
            children: [
              if (error != null)
                _Note(error!)
              else if (loading)
                const _Note('Cargando usuarios…')
              else if (users.isEmpty)
                const _Note('Todavía no hay cuentas registradas.')
              else
                for (final account in users.take(5)) _UserRow(user: account),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _ImplementationStatus(),
      ],
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.users,
    required this.error,
    required this.loading,
  });

  final List<AppUser> users;
  final String? error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _Note(error!),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: _Note('Cargando usuarios…'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          '${users.length} cuentas visibles para tu rol',
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 14),
        _Card(
          title: 'Todas las cuentas',
          subtitle: 'Pasajeros, conductores y equipo administrativo.',
          child: Column(
            children: [
              if (users.isEmpty)
                const _Note('Todavía no hay cuentas registradas.')
              else
                for (final account in users) _UserRow(user: account),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AppUser user;

  String get _date {
    final createdAt = user.createdAt;
    if (createdAt == null) return 'Sin fecha';
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final day = createdAt.day.toString().padLeft(2, '0');
    return '$day ${months[createdAt.month - 1]} ${createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: user.role.accentSoft,
            child: Text(
              user.initials,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: user.role.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: user.role.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  user.role.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: user.role.accent,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _date,
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImplementationStatus extends StatelessWidget {
  const _ImplementationStatus();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (true, 'Acceso por roles', 'Admin y superadmin diferenciados'),
      (true, 'Primer acceso seguro', 'Cambio de contraseña administrativa'),
      (false, 'Conexión con Supabase', 'Preparada para el integrador'),
      (false, 'Gestión de viajes', 'Siguiente módulo funcional'),
    ];

    return _Card(
      title: 'Estado de implementación',
      subtitle: 'Avance funcional del proyecto.',
      child: Column(
        children: [
          for (final (index, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: step.$1 ? AppColors.greenSoft : AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: step.$1 ? AppColors.green : AppColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: step.$1
                        ? const Icon(Icons.check, size: 14, color: AppColors.green)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.inkMuted,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.$2,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          step.$3,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.section, required this.onBack});

  final _Section section;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.purpleSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(section.icon, size: 28, color: AppColors.purple),
            ),
            const SizedBox(height: 18),
            Text(
              section.label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Este módulo se construirá en una siguiente etapa.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(onPressed: onBack, child: const Text('Volver al resumen')),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}
