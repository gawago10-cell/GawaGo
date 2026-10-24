import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';

/// Brand intro played over the landing page when the app opens signed out,
/// then dissolved on its own -- the same animation as the web intro
/// (frontend/src/components/IntroSplash.jsx). Households (cream) and workers
/// (green) pair up, meet at a door, and the house and wordmark appear.
/// Tapping anywhere skips straight to the fade.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key, required this.onDone});

  /// Called once the intro has faded out; the caller removes it.
  final VoidCallback onDone;

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

// Timeline in ms; the overlay fades from _tLeave to _tTotal.
const _tLines = 550.0;
const _tConv = 1450.0;
const _tMerge = 1950.0;
const _tHouse = 1990.0;
const _tDoor = 2500.0;
const _tReveal = 2650.0;
const _tEnd = 2900.0;
const _tLeave = 3900.0;
const _tTotal = 4450.0;

double _clamp(double x) => x.clamp(0.0, 1.0).toDouble();
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _easeIO(double x) =>
    x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;

class _IntroSplashState extends State<IntroSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4450),
  );
  final _stackKey = GlobalKey();
  final _houseKey = GlobalKey();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect the system's reduce-motion setting: no intro at all.
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      return;
    }
    // A status listener, not forward().whenComplete: skipping restarts the
    // controller, which cancels the first forward's future, so that callback
    // never ran and a tapped intro stayed over the landing page.
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    final leaveAt = _tLeave / _tTotal;
    if (_controller.value < leaveAt) {
      _controller.value = leaveAt;
      _controller.forward();
    }
  }

  /// Door position in the stack's coordinates, where the pairs converge.
  Offset? _doorCenter() {
    final house = _houseKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (house == null || stack == null || !house.hasSize) return null;
    final s = house.size.width / 200;
    return house.localToGlobal(
      Offset(100 * s, (128 + 42 * .6) * s),
      ancestor: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final houseSize = math.min(220.0, width * .52);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * _tTotal;
        if (MediaQuery.of(context).disableAnimations) {
          return const SizedBox.shrink();
        }
        final legend =
            _clamp((t - 350) / 500) * (1 - _clamp((t - _tHouse) / 500));
        final tagline = _clamp((t - _tReveal - 450) / 600);
        return Opacity(
          opacity: 1 - _clamp((t - _tLeave) / (_tTotal - _tLeave)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            // Material, not a plain box: it sits above the landing page's
            // Scaffold, and text with no Material ancestor falls back to
            // Flutter's heavy debug style.
            child: Material(
              color: GawaGoColors.sidebar,
              child: Stack(
                key: _stackKey,
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _PairsPainter(t, _doorCenter)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: _houseKey,
                          width: houseSize,
                          height: houseSize,
                          child: CustomPaint(painter: _HousePainter(t)),
                        ),
                        const SizedBox(height: 6),
                        _Wordmark(t: t, width: width),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: tagline,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - tagline)),
                            child: Text.rich(
                              const TextSpan(
                                text: 'Bawat gawa, ',
                                children: [
                                  TextSpan(
                                    text: 'may kapares.',
                                    style: TextStyle(
                                      color: GawaGoColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                fontFamily: GawaGoColors.fontBody,
                                fontSize: (width * .022).clamp(14.0, 18.0),
                                color: GawaGoColors.mutedText,
                                letterSpacing: .3,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 26,
                    left: 0,
                    right: 0,
                    child: Opacity(opacity: legend, child: const _Legend()),
                  ),
                  Positioned(
                    bottom: MediaQuery.paddingOf(context).bottom + 26,
                    left: 0,
                    right: 0,
                    child: const Text(
                      'TAP ANYWHERE TO SKIP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: GawaGoColors.fontBody,
                        fontSize: 12.5,
                        letterSpacing: .8,
                        color: Color(0x99C2CBAF),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontFamily: GawaGoColors.fontBody,
            fontSize: 12,
            letterSpacing: .7,
            color: Color(0xBFC2CBAF),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(GawaGoColors.cream, 'HOUSEHOLDS'),
        const SizedBox(width: 20),
        item(GawaGoColors.primary, 'WORKERS'),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.t, required this.width});

  final double t;
  final double width;

  static const _letters = [
    ('G', 2, false),
    ('a', 1, false),
    ('w', 0, false),
    ('a', 0, false),
    ('G', 1, true),
    ('o', 2, true),
  ];

  @override
  Widget build(BuildContext context) {
    final fontSize = (width * .09).clamp(46.0, 84.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (ch, delay, go) in _letters)
          Builder(
            builder: (context) {
              final p = _clamp((t - _tReveal - delay * 80) / 600);
              final e = Curves.easeOutBack.transform(p);
              return Opacity(
                opacity: p,
                child: Transform.translate(
                  offset: Offset(0, fontSize * .3 * (1 - e)),
                  child: Transform.scale(
                    scale: .85 + .15 * e,
                    child: Text(
                      ch,
                      style: TextStyle(
                        fontFamily: GawaGoColors.fontHeading,
                        fontWeight: FontWeight.w800,
                        fontSize: fontSize,
                        height: 1,
                        letterSpacing: -fontSize * .02,
                        color: go ? GawaGoColors.primary : GawaGoColors.cream,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Pair {
  _Pair(this.hx, this.hy, this.wx, this.wy, this.ph, this.delay);
  final double hx, hy, wx, wy, ph, delay;
}

/// Household/worker pairs, their matching lines, and the rings at the door.
class _PairsPainter extends CustomPainter {
  _PairsPainter(this.t, this.doorCenter);

  final double t;
  final Offset? Function() doorCenter;

  static const _cream = GawaGoColors.cream;
  static const _green = GawaGoColors.primary;

  static List<_Pair> _build(Size size) {
    var seed = 11;
    double r() {
      seed = (seed * 16807) % 2147483647;
      return (seed - 1) / 2147483646;
    }

    final w = size.width, h = size.height;
    final n = w < 600 ? 10 : 16;
    final radius = math.min(w, h) * .44;
    const m = 30.0;
    final pairs = <_Pair>[];
    for (var i = 0; i < n; i++) {
      final a = (i / n) * math.pi * 2 + r() * .5;
      final d = radius * (.5 + .5 * r());
      final hx = w / 2 + math.cos(a) * d * (w > h ? 1.45 : 1);
      final hy = h / 2 + math.sin(a) * d * (w > h ? .85 : 1.2);
      final oa = r() * math.pi * 2, od = 45 + r() * 70;
      final wx = hx + math.cos(oa) * od, wy = hy + math.sin(oa) * od;
      pairs.add(
        _Pair(
          hx.clamp(m, w - m),
          hy.clamp(m, h - m),
          wx.clamp(m, w - m),
          wy.clamp(m, h - m),
          r() * 6.28,
          r(),
        ),
      );
    }
    return pairs;
  }

  void _dot(Canvas c, double x, double y, double rad, Color color,
      double alpha, bool glow) {
    if (rad <= 0 || alpha <= 0) return;
    if (glow) {
      c.drawCircle(
        Offset(x, y),
        rad * 2.6,
        Paint()..color = color.withValues(alpha: .16 * alpha),
      );
    }
    c.drawCircle(Offset(x, y), rad, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= _tEnd) return;
    final door = doorCenter() ?? size.center(Offset.zero);
    final tx = door.dx, ty = door.dy;
    final conv = _easeIO(_clamp((t - _tConv) / (_tMerge - _tConv)));
    final merge = _easeIO(_clamp((t - _tMerge) / 250));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final p in _build(size)) {
      final appear = _clamp((t - p.delay * 450) / 300);
      final dx = math.sin(t / 900 + p.ph) * 5, dy = math.cos(t / 1100 + p.ph) * 5;
      final hx = _lerp(p.hx + dx, tx - 8 * (1 - merge), conv);
      final hy = _lerp(p.hy + dy, ty, conv);
      final wx = _lerp(p.wx - dx, tx + 8 * (1 - merge), conv);
      final wy = _lerp(p.wy - dy, ty, conv);

      final ls = _tLines + p.delay * 400;
      final lp = _easeIO(_clamp((t - ls) / 450));
      if (lp > 0) {
        final fade = 1 - conv;
        line.color = _green.withValues(alpha: .5 * fade);
        canvas.drawLine(
          Offset(hx, hy),
          Offset(_lerp(hx, wx, lp), _lerp(hy, wy, lp)),
          line,
        );
        if (lp >= 1 && fade > 0) {
          final k = ((t - ls - 450) % 900) / 900;
          final pk = k < .5 ? k * 2 : 2 - k * 2;
          _dot(canvas, _lerp(hx, wx, pk), _lerp(hy, wy, pk), 2.2, _green,
              .9 * fade, true);
        } else if (lp < 1) {
          _dot(canvas, _lerp(hx, wx, lp), _lerp(hy, wy, lp), 2.6, _green, 1,
              true);
        }
      }

      final dotSize = 4.5 * (1 - merge * .6);
      final alpha = appear * (1 - _clamp((t - _tMerge - 120) / 180));
      _dot(canvas, hx, hy, dotSize * appear, _cream, alpha, false);
      _dot(canvas, wx, wy, dotSize * appear, _green, alpha, true);
    }

    // the merged pair waits at the door, then becomes the door light
    if (t >= _tMerge) {
      final fadeOut = 1 - _clamp((t - _tDoor) / 250);
      final breathe = 1 + math.sin((t - _tMerge) / 140) * .08;
      _dot(canvas, tx, ty, (5 + merge * 4) * breathe * fadeOut, _green,
          fadeOut, true);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final short = math.min(size.width, size.height);
      final f = _clamp((t - _tMerge) / 600);
      ring.color = _green.withValues(alpha: .8 * (1 - f));
      canvas.drawCircle(Offset(tx, ty), 10 + f * short * .35, ring);
      final f2 = _clamp((t - _tMerge - 150) / 600);
      if (f2 > 0) {
        ring.color = _green.withValues(alpha: .5 * (1 - f2));
        canvas.drawCircle(Offset(tx, ty), 10 + f2 * short * .25, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_PairsPainter old) => old.t != t;
}

/// The house outline drawing itself in, then the door and windows lighting.
class _HousePainter extends CustomPainter {
  _HousePainter(this.t);

  final double t;

  static Path _partial(Path path, double progress) {
    if (progress <= 0) return Path();
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.scale(s);
    final h = t - _tHouse;
    final d = t - _tDoor;
    const draw = Cubic(.6, .1, .2, 1);

    // glow behind the house
    final g = _clamp(d / 1000);
    final glow = g <= 0 ? 0.0 : (g < .4 ? .55 * g / .4 : .55 - .3 * (g - .4) / .6);
    if (glow > 0) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(100, 120), width: 124, height: 108),
        Paint()
          ..color = GawaGoColors.primary.withValues(alpha: glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }

    // windows and door fill
    final win = _clamp((d - 250) / 350) * .85;
    if (win > 0) {
      final paint = Paint()..color = GawaGoColors.primary.withValues(alpha: win);
      for (final x in [66.0, 116.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 104, 18, 18), const Radius.circular(3)),
          paint,
        );
      }
    }
    final door = _clamp(d / 450);
    if (door > 0) {
      final height = 44 * (.15 + .85 * Curves.easeOutBack.transform(door));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(86, 170 - height, 28, height),
          const Radius.circular(3),
        ),
        Paint()..color = GawaGoColors.primary.withValues(alpha: door),
      );
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    stroke
      ..color = GawaGoColors.cream.withValues(alpha: .35)
      ..strokeWidth = 2;
    canvas.drawPath(
      _partial(Path()..moveTo(20, 170)..lineTo(180, 170),
          Curves.ease.transform(_clamp(h / 400))),
      stroke,
    );
    stroke
      ..color = GawaGoColors.cream
      ..strokeWidth = 3.4;
    canvas.drawPath(
      _partial(Path()..moveTo(34, 96)..lineTo(100, 38)..lineTo(166, 96),
          draw.transform(_clamp((h - 50) / 450))),
      stroke,
    );
    canvas.drawPath(
      _partial(
          Path()..moveTo(52, 82)..lineTo(52, 170)..lineTo(148, 170)..lineTo(148, 82),
          draw.transform(_clamp((h - 200) / 500))),
      stroke,
    );
    canvas.drawPath(
      _partial(
          Path()..moveTo(86, 170)..lineTo(86, 128)..lineTo(114, 128)..lineTo(114, 170),
          Curves.ease.transform(_clamp((h - 400) / 300))),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_HousePainter old) => old.t != t;
}
