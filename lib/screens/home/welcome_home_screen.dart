import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ride_colors.dart';
import '../../widgets/ride_logo.dart';

/// Presentación breve de Ride antes del acceso, adaptable a móvil y escritorio.
class WelcomeHomeScreen extends StatelessWidget {
  const WelcomeHomeScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Scaffold(
      backgroundColor: ride.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            final compactHeight = constraints.maxHeight < 680;
            final content = _WelcomeContent(
              wide: wide,
              compact: compactHeight,
              onContinue: onContinue,
            );
            if (wide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1500),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ride.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: ride.border),
                        boxShadow: [
                          BoxShadow(
                            color: ride.shadow,
                            blurRadius: 42,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(29),
                        child: Row(
                          children: [
                            const Expanded(
                              flex: 12,
                              child: _HeroVisual(wide: true),
                            ),
                            Expanded(flex: 9, child: content),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            final heroHeight = compactHeight
                ? (constraints.maxHeight * 0.34).clamp(150.0, 215.0)
                : (constraints.maxHeight * 0.46).clamp(250.0, 430.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: heroHeight,
                      child: _HeroVisual(compact: compactHeight),
                    ),
                    content,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({
    required this.wide,
    required this.compact,
    required this.onContinue,
  });

  final bool wide;
  final bool compact;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = wide ? 54.0 : (width < 360 ? 20.0 : 28.0);
    return Container(
      color: ride.surface,
      padding: EdgeInsets.fromLTRB(
        horizontal,
        compact ? 22 : (wide ? 48 : 34),
        horizontal,
        compact ? 24 : (wide ? 48 : 40),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Text(
                'BIENVENIDO A RIDE',
                style: TextStyle(
                  color: ride.accent,
                  fontSize: AppText.micro,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: compact ? 7 : 12),
              Text(
                'Tu camino, más simple desde el inicio.',
                textAlign: wide ? TextAlign.left : TextAlign.center,
                style: AppTheme.display(
                  compact ? 24 : (wide ? 38 : 29),
                  color: ride.ink,
                  letterSpacing: -1.2,
                  height: 1.12,
                ),
              ),
              SizedBox(height: compact ? 8 : 14),
              Text(
                'Solicita un viaje, sigue el recorrido y mantén todo bajo control desde un solo lugar.',
                textAlign: wide ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  color: ride.inkMuted,
                  fontSize: compact ? AppText.label : AppText.small,
                  height: compact ? 1.4 : 1.55,
                ),
              ),
              SizedBox(height: compact ? 14 : 26),
              if (!compact)
                Wrap(
                  alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _Benefit(icon: Icons.route_outlined, label: 'Rutas claras'),
                    _Benefit(
                      icon: Icons.shield_outlined,
                      label: 'Viajes seguros',
                    ),
                    _Benefit(
                      icon: Icons.payments_outlined,
                      label: 'Precio visible',
                    ),
                  ],
                ),
              SizedBox(height: compact ? 0 : 30),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onContinue,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 21),
                  label: const Text('Empezar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: ride.surfaceAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: ride.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ride.accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: ride.inkMuted,
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroVisual extends StatefulWidget {
  const _HeroVisual({this.wide = false, this.compact = false});
  final bool wide;
  final bool compact;

  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _curve(double begin, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final dark = ride.isDark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final unit = (width < height ? width : height).clamp(260.0, 720.0);
        final personWidth = (unit * (widget.wide ? 0.20 : 0.24)).clamp(
          70.0,
          145.0,
        );
        final carWidth = (unit * (widget.wide ? 0.36 : 0.40)).clamp(
          130.0,
          260.0,
        );
        return ClipRect(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: ride.hero),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    dark
                        ? const Color(0xFF0B2838)
                        : Colors.white.withValues(alpha: 0.18),
                    dark ? BlendMode.multiply : BlendMode.screen,
                  ),
                  child: Image.asset(
                    'assets/images/fondoInicio.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: dark
                          ? const [
                              Color(0x22030C14),
                              Color(0x55030C14),
                              Color(0xF2061420),
                            ]
                          : const [
                              Color(0x08FFFFFF),
                              Color(0x00FFFFFF),
                              Color(0xDDF1F5FA),
                            ],
                    ),
                  ),
                ),
                Positioned(
                  top: (height * 0.08).clamp(18.0, 46.0),
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      RideWordmark(
                        markSize: (unit * 0.095).clamp(34.0, 58.0),
                        fontSize: (unit * 0.075).clamp(23.0, 39.0),
                        color: dark ? Colors.white : ride.ink,
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Muévete con libertad.',
                          style: AppTheme.display(
                            (unit * 0.045).clamp(16.0, 25.0),
                            color: dark
                                ? const Color(0xFFB8CFDB)
                                : ride.inkMuted,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: width * 0.035,
                  bottom: height * 0.04,
                  child: _Entrance(
                    animation: _curve(0.05, 0.72),
                    from: const Offset(-0.9, 0),
                    child: Image.asset(
                      'assets/images/ChicaDibujo.png',
                      width: personWidth,
                    ),
                  ),
                ),
                Positioned(
                  right: width * 0.04,
                  bottom: height * 0.04,
                  child: _Entrance(
                    animation: _curve(0.18, 0.82),
                    from: const Offset(0.9, 0),
                    child: Image.asset(
                      'assets/images/ChicoDibujo.png',
                      width: personWidth,
                    ),
                  ),
                ),
                Positioned(
                  right: widget.wide ? width * 0.17 : width * 0.16,
                  bottom: widget.wide ? height * 0.02 : -height * 0.02,
                  child: _Entrance(
                    animation: _curve(0.32, 1),
                    from: const Offset(1.1, 0.12),
                    child: Image.asset(
                      'assets/images/carroDibujo.png',
                      width: carWidth,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.from,
    required this.child,
  });
  final Animation<double> animation;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: from,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
