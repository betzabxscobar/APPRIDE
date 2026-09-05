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
            final compactLayout =
                constraints.maxHeight < 620 || constraints.maxWidth < 320;
            final content = _WelcomeContent(
              wide: wide,
              compact: compactLayout,
              centerVertically: constraints.maxHeight >= 900,
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
            final heroHeight = compactLayout
                ? (constraints.maxHeight * 0.34).clamp(150.0, 215.0)
                : constraints.maxHeight < 720
                ? (constraints.maxHeight * 0.40).clamp(240.0, 285.0)
                : (constraints.maxHeight * 0.46).clamp(250.0, 430.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: heroHeight,
                      child: _HeroVisual(compact: compactLayout),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - heroHeight + 24,
                        ),
                        child: content,
                      ),
                    ),
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
    required this.centerVertically,
    required this.onContinue,
  });

  final bool wide;
  final bool compact;
  final bool centerVertically;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = wide ? 54.0 : (width < 360 ? 20.0 : 28.0);
    final panel = ride.isDark ? const Color(0xFF081F2D) : ride.surface;
    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: wide
            ? null
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: ride.isDark && !wide
            ? Border(top: BorderSide(color: ride.borderStrong))
            : null,
      ),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        compact ? 22 : (wide ? 48 : 34),
        horizontal,
        compact ? 24 : (wide ? 48 : 40),
      ),
      child: Align(
        alignment: wide || centerVertically
            ? Alignment.center
            : Alignment.topCenter,
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
                compact
                    ? 'Tu viaje empieza aquí.'
                    : 'Tu camino, más simple desde el inicio.',
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
                compact
                    ? 'Solicita y sigue tu viaje desde un solo lugar.'
                    : 'Solicita un viaje, sigue el recorrido y mantén todo bajo control desde un solo lugar.',
                textAlign: wide ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  color: ride.inkMuted,
                  fontSize: compact ? AppText.label : AppText.small,
                  height: compact ? 1.4 : 1.55,
                ),
              ),
              SizedBox(height: compact ? 14 : 26),
              Wrap(
                alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                spacing: compact ? 7 : 10,
                runSpacing: compact ? 7 : 10,
                children: [
                  _Benefit(
                    icon: Icons.route_outlined,
                    label: compact ? 'Rutas' : 'Rutas claras',
                  ),
                  _Benefit(
                    icon: Icons.shield_outlined,
                    label: compact ? 'Seguro' : 'Viajes seguros',
                  ),
                  _Benefit(
                    icon: Icons.payments_outlined,
                    label: compact ? 'Precio' : 'Precio visible',
                  ),
                ],
              ),
              SizedBox(height: compact ? 18 : 30),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onContinue,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? const Color(0xFF00E5FF)
                          : null,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? Colors.black
                          : null,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? const BorderSide(color: Colors.black, width: 2)
                          : null,
                    ),
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? Colors.transparent
                          : null,
                    ),
                  ),
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
    final chipColor = ride.isDark ? const Color(0xFF14536B) : ride.surfaceAlt;
    final chipBorder = ride.isDark ? const Color(0xFF2A7890) : ride.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ride.accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ride.inkMuted,
                fontSize: AppText.label,
                fontWeight: FontWeight.w700,
              ),
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
        return ClipRect(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: ride.hero),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (dark)
                  Image.asset(
                    'assets/images/fondoInicioOscuro-v2.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  )
                else
                  ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.white.withValues(alpha: 0.18),
                      BlendMode.screen,
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
                              Color(0x1A061F31),
                              Color(0x08061F31),
                              Color(0x72030F19),
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
                                ? const Color(0xFFE2F0F5)
                                : ride.inkMuted,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: widget.wide ? height * 0.035 : 24,
                  height: (height * (widget.wide ? 0.46 : 0.52)).clamp(
                    92.0,
                    widget.wide ? 310.0 : 205.0,
                  ),
                  child: _RideScene(
                    wide: widget.wide,
                    girlAnimation: _curve(0.05, 0.72),
                    boyAnimation: _curve(0.18, 0.82),
                    carAnimation: _curve(0.32, 1),
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

/// Escena con una sola línea de suelo para que personas y vehículo compartan
/// perspectiva en cualquier tamaño de pantalla.
class _RideScene extends StatelessWidget {
  const _RideScene({
    required this.wide,
    required this.girlAnimation,
    required this.boyAnimation,
    required this.carAnimation,
  });

  final bool wide;
  final Animation<double> girlAnimation;
  final Animation<double> boyAnimation;
  final Animation<double> carAnimation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final personHeight = (height * 0.96).clamp(82.0, wide ? 285.0 : 178.0);
        final girlWidth = personHeight * 619 / 1958;
        final boyWidth = personHeight * 607 / 1900;
        final carWidth = (width * (wide ? 0.40 : 0.43)).clamp(
          116.0,
          wide ? 345.0 : 220.0,
        );
        final carHeight = carWidth * 562 / 1186;
        final sideInset = (width * (wide ? 0.075 : 0.07)).clamp(12.0, 58.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (width - carWidth * 0.72) / 2,
              bottom: 0,
              width: carWidth * 0.72,
              height: (carHeight * 0.10).clamp(5.0, 13.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF020B12).withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: sideInset,
              bottom: 0,
              child: _Entrance(
                animation: girlAnimation,
                from: const Offset(-0.55, 0),
                child: _TrimmedAsset(
                  asset: 'assets/images/ChicaDibujo.png',
                  sourceLeft: 405,
                  sourceTop: 226,
                  sourceWidth: 619,
                  sourceHeight: 1958,
                  width: girlWidth,
                  height: personHeight,
                ),
              ),
            ),
            Positioned(
              right: sideInset,
              bottom: 0,
              child: _Entrance(
                animation: boyAnimation,
                from: const Offset(0.55, 0),
                child: _TrimmedAsset(
                  asset: 'assets/images/ChicoDibujo.png',
                  sourceLeft: 417,
                  sourceTop: 233,
                  sourceWidth: 607,
                  sourceHeight: 1900,
                  width: boyWidth,
                  height: personHeight,
                ),
              ),
            ),
            Positioned(
              left: (width - carWidth) / 2,
              bottom: 1,
              child: _Entrance(
                animation: carAnimation,
                from: const Offset(0.75, 0),
                child: _TrimmedAsset(
                  asset: 'assets/images/carroDibujo.png',
                  sourceLeft: 89,
                  sourceTop: 940,
                  sourceWidth: 1186,
                  sourceHeight: 562,
                  width: carWidth,
                  height: carHeight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Recorta en tiempo de composición el espacio transparente de una imagen.
/// Así las medidas describen el dibujo visible, no el lienzo original.
class _TrimmedAsset extends StatelessWidget {
  const _TrimmedAsset({
    required this.asset,
    required this.sourceLeft,
    required this.sourceTop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
  });

  static const double _sourceCanvasWidth = 1340;
  static const double _sourceCanvasHeight = 2400;

  final String asset;
  final double sourceLeft;
  final double sourceTop;
  final double sourceWidth;
  final double sourceHeight;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scale = width / sourceWidth;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -sourceLeft * scale,
              top: -sourceTop * scale,
              width: _sourceCanvasWidth * scale,
              height: _sourceCanvasHeight * scale,
              child: Image.asset(asset, fit: BoxFit.fill),
            ),
          ],
        ),
      ),
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
