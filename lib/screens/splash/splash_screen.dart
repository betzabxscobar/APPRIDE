import 'package:flutter/material.dart';

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
  bool _started = false;

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
      });

    // Zoom lento continuo en la imagen de fondo
    _zoomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
      _zoomCtrl.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone();
      });
    } else {
      _ctrl.forward();
      _zoomCtrl.forward();
    }
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
    final begin =
        _durations[delayIndex].inMilliseconds / _totalDuration.inMilliseconds;
    final end =
        (begin + _fadeDuration.inMilliseconds / _totalDuration.inMilliseconds)
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
    final dark = ride.isDark;
    return Scaffold(
      backgroundColor: ride.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Imagen de fondo con zoom ──
          AnimatedBuilder(
            animation: _zoomCtrl,
            builder: (context, child) {
              final scale =
                  1.0 + Curves.easeOut.transform(_zoomCtrl.value) * 0.15;
              return Transform.scale(scale: scale, child: child);
            },
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                dark ? const Color(0xFF4B9CB5) : Colors.white,
                dark ? BlendMode.multiply : BlendMode.dst,
              ),
              child: Image.asset(
                'assets/images/fondo.png',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [Color(0x330A3047), Color(0x88104E66)]
                      : const [Color(0x18FFFFFF), Color(0x77F1F5FA)],
                ),
              ),
            ),
          ),

          // ── Capa con los elementos animados ──
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shortest = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                final logoSize = (shortest * 0.25).clamp(90.0, 160.0);
                final compact = constraints.maxHeight < 650;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 380 ? 24 : 40,
                      vertical: compact ? 16 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo
                          _fade(
                            Image.asset(
                              'assets/images/logo.png',
                              width: logoSize,
                              height: logoSize,
                            ),
                            0,
                          ),
                          SizedBox(height: compact ? 12 : 24),

                          // Título "Ride"
                          _fade(
                            Text(
                              'Ride',
                              style: AppTheme.display(
                                (shortest * 0.09).clamp(38.0, 58.0),
                                color: ride.ink,
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
                                (shortest * 0.04).clamp(17.0, 22.0),
                                color: ride.inkMuted,
                                letterSpacing: 0,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            2,
                          ),

                          SizedBox(height: compact ? 20 : 40),

                          // Pilares de marca
                          _buildPillars(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillars() {
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
          _fade(_PillarTile(data: pillars[i]), 3 + i),
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
  const _PillarTile({required this.data});

  final _PillarData data;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: ride.accentSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ride.border),
            ),
            child: Icon(data.icon, size: 30, color: ride.accent),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: AppTheme.display(19, color: ride.ink, height: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  style: AppTheme.display(
                    15,
                    color: ride.inkMuted,
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
