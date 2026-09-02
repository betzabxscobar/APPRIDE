import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';

/// Pantalla de bienvenida que muestra el logo y los pilares de marca
/// con una animación secuencial de fade-in sobre la imagen de fondo.
///
/// Se muestra al inicio de la app y, al completar la animación (~3.5 s),
/// ejecuta [onDone] para navegar a la siguiente pantalla.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  /// Callback que se ejecuta cuando termina la animación del splash.
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _zoomCtrl;

  /// Cada elemento aparece con un delay progresivo.
  static const _durations = [
    Duration(milliseconds: 400), // logo
    Duration(milliseconds: 700), // título
    Duration(milliseconds: 950), // subtítulo
    Duration(milliseconds: 1300), // seguro
    Duration(milliseconds: 1600), // sostenible
    Duration(milliseconds: 1900), // confiable
  ];

  static const _fadeDuration = Duration(milliseconds: 600);
  static const _totalDuration = Duration(milliseconds: 3500);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _totalDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onDone();
        }
      })
      ..forward();

    // Zoom lento continuo en la imagen de fondo
    _zoomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  /// Envuelve [child] con un [FadeTransition] que inicia en el [delay]
  /// indicado dentro de la animación total de [_ctrl].
  Widget _fade(Widget child, int delayIndex) {
    final begin = _durations[delayIndex].inMilliseconds / _totalDuration.inMilliseconds;
    final end = (begin + _fadeDuration.inMilliseconds / _totalDuration.inMilliseconds)
        .clamp(0.0, 1.0);

    final tween = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(begin, end, curve: Curves.easeOut),
      ),
    );

    return FadeTransition(opacity: tween, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final isDark = ride.isDark;

    return Scaffold(
      backgroundColor: ride.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Imagen de fondo con zoom + filtro para modo oscuro ──
          AnimatedBuilder(
            animation: _zoomCtrl,
            builder: (context, child) {
              final scale = 1.0 + Curves.easeOut.transform(_zoomCtrl.value) * 0.15;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/fondo.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
                // Filtro para modo oscuro: velo ligero para que la ilustración
                // siga viéndose pero el texto blanco contraste. Antes tapaba
                // con 0xCC (80%), ahora 0x59 (35%) deja ver el fondo.
                if (isDark)
                  Container(
                    color: const Color(0x59061420),
                  ),
              ],
            ),
          ),

          // ── Capa con los elementos animados ──
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    _fade(
                      Image.asset(
                        'assets/images/logo.png',
                        width: 160,
                        height: 160,
                      ),
                      0,
                    ),
                    const SizedBox(height: 24),

                    // Título "Ride"
                    _fade(
                      Text(
                        'Ride',
                        style: AppTheme.display(
                          58,
                          color: isDark ? Colors.white : AppColors.ink,
                          letterSpacing: -1.5,
                          height: 1,
                        ),
                      ),
                      1,
                    ),
                    const SizedBox(height: 12),

                    // Subtítulo
                    _fade(
                      Text(
                        'Muévete a tu manera',
                        style: AppTheme.display(
                          22,
                          color: isDark ? const Color(0xFFB4C8D3) : AppColors.inkMuted,
                          letterSpacing: 0,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      2,
                    ),

                    const SizedBox(height: 40),

                    // Pilares de marca
                    _buildPillars(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillars() {
    final isDark = context.ride.isDark;
    final pillars = [
      _PillarData(
        icon: Icons.shield_outlined,
        title: 'Seguro',
        subtitle: 'Tecnología que\nte cuida',
      ),
      _PillarData(
        icon: Icons.eco_outlined,
        title: 'Sostenible',
        subtitle: 'Menos emisiones,\nmás futuro',
      ),
      _PillarData(
        icon: Icons.favorite_outline,
        title: 'Confiable',
        subtitle: 'Personas reales,\nviajes merecidos',
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pillars.length; i++)
          _fade(_PillarTile(data: pillars[i], isDark: isDark), 3 + i),
      ],
    );
  }
}

class _PillarData {
  const _PillarData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _PillarTile extends StatelessWidget {
  const _PillarTile({required this.data, this.isDark = false});

  final _PillarData data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14314B) : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
              border: isDark ? Border.all(color: const Color(0xFF1E3D52), width: 1) : null,
            ),
            child: Icon(
              data.icon,
              size: 30,
              color: isDark ? const Color(0xFF56B6F8) : AppColors.primary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: AppTheme.display(
                    19,
                    color: isDark ? Colors.white : AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  style: AppTheme.display(
                    15,
                    color: isDark ? const Color(0xFF9CB2C4) : AppColors.inkMuted,
                    height: 1.3,
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
