import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Brand colors matching the CSS effects
class MakawEffects {
  static const Color primaryBlue = Color(0xFF7C9CFF);
  static const Color glowBlue = Color(0xFF7C9CFF);
  static const Color accentPink = Color(0xFFFF4D8D);
  static const Color accentCyan = Color(0xFF38F5FF);

  static const Duration defaultDuration = Duration(milliseconds: 2200);

  // ─── Spin & Reveal ──────────────────────────────────────────────────────────
  /// 3D Y-axis spin with scale and glow — CSS spinReveal
  static Widget spinReveal({
    required Widget child,
    Duration duration = const Duration(milliseconds: 2000),
    VoidCallback? onComplete,
  }) {
    return _SpinRevealWidget(
      duration: duration,
      onComplete: onComplete,
      child: child,
    );
  }

  // ─── Pulse Breathing ───────────────────────────────────────────────────────
  /// Gentle scale pulse with blue glow — CSS pulseBreath
  static Widget pulseBreath({
    required Widget child,
    Duration period = const Duration(milliseconds: 1800),
  }) {
    return _PulseBreathWidget(period: period, child: child);
  }

  // ─── 3D Flip Card ──────────────────────────────────────────────────────────
  /// Two-sided Y-axis flip — CSS flip3d
  static Widget flip3D({
    required Widget front,
    required Widget back,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    return _Flip3DWidget(duration: duration, front: front, back: back);
  }

  // ─── Glitch ────────────────────────────────────────────────────────────────
  /// Chromatic aberration glitch — CSS glitchX
  static Widget glitch({
    required Widget child,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return _GlitchWidget(duration: duration, child: child);
  }

  // ─── Typewriter / Draw Clip ────────────────────────────────────────────────
  /// Typewriter clip-path reveal — CSS drawClip + cursorBlink
  static Widget typewriter({
    required String text,
    required TextStyle style,
    Duration duration = const Duration(milliseconds: 2400),
    bool showCursor = true,
  }) {
    return _TypewriterWidget(
      text: text,
      style: style,
      duration: duration,
      showCursor: showCursor,
    );
  }

  // ─── Aurora Orbit ──────────────────────────────────────────────────────────
  /// Orbital particles around a center — CSS orbitA/orbitB
  static Widget auroraOrbit({
    required Widget child,
    double orbitRadius = 62,
    double orbit2Radius = 48,
    Color orbitColor = const Color(0xFF7C9CFF),
    Color orbit2Color = const Color(0xFF9F7AEA),
  }) {
    return _AuroraOrbitWidget(
      orbitRadius: orbitRadius,
      orbit2Radius: orbit2Radius,
      orbitColor: orbitColor,
      orbit2Color: orbit2Color,
      child: child,
    );
  }

  // ─── Loading Ring ──────────────────────────────────────────────────────────
  /// Conic gradient ring spinner — CSS ringSpin + ringFill
  static Widget loadingRing({
    double size = 48,
    double strokeWidth = 4,
    Color color = const Color(0xFF7C9CFF),
  }) {
    return _LoadingRingWidget(size: size, strokeWidth: strokeWidth, color: color);
  }

  // ─── Morph Feather ─────────────────────────────────────────────────────────
  /// Two-widget cross-fade morph — CSS morphOut/morphIn
  static Widget morphFeather({
    required Widget a,
    required Widget b,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    return _MorphFeatherWidget(duration: duration, a: a, b: b);
  }

  // ─── Makaw Logo with effects ───────────────────────────────────────────────
  /// Complete Makaw logo presentation with spin-reveal + breathing pulse
  static Widget logoPresentation({
    double size = 120,
    bool animate = true,
  }) {
    if (!animate) {
      return Image.asset(
        'assets/makaw_logo_64.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return spinReveal(
      child: pulseBreath(
        child: Image.asset(
          'assets/makaw_logo_64.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Makaw logo with aurora orbit particles
  static Widget logoWithOrbit({
    double size = 80,
    Color? glowColor,
  }) {
    return auroraOrbit(
      orbitColor: glowColor ?? primaryBlue,
      orbit2Color: const Color(0xFF9F7AEA),
      child: Image.asset(
        'assets/makaw_logo_64.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

// ─── Spin & Reveal Implementation ─────────────────────────────────────────────
class _SpinRevealWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback? onComplete;
  const _SpinRevealWidget({required this.child, required this.duration, this.onComplete});

  @override
  State<_SpinRevealWidget> createState() => _SpinRevealWidgetState();
}

class _SpinRevealWidgetState extends State<_SpinRevealWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotateAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _brightnessAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _rotateAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.5), weight: 45),
      TweenSequenceItem(tween: ConstantTween(0.5), weight: 7),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.0), weight: 48),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _scaleAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.12), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _brightnessAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.2), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 55),
    ]).animate(_controller);
    _controller.forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_rotateAnim.value * math.pi)
            ..setEntry(0, 0, _scaleAnim.value)
            ..setEntry(1, 1, _scaleAnim.value)
            ..setEntry(2, 2, _scaleAnim.value),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(<double>[
              _brightnessAnim.value, 0, 0, 0, 0,
              0, _brightnessAnim.value, 0, 0, 0,
              0, 0, _brightnessAnim.value, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ─── Pulse Breathing Implementation ───────────────────────────────────────────
class _PulseBreathWidget extends StatefulWidget {
  final Widget child;
  final Duration period;
  const _PulseBreathWidget({required this.child, required this.period});

  @override
  State<_PulseBreathWidget> createState() => _PulseBreathWidgetState();
}

class _PulseBreathWidgetState extends State<_PulseBreathWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        final v = _controller.value;
        final scale = 1.0 + v * 0.08;
        final glowOpacity = v * 0.55;
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MakawEffects.glowBlue..withValues(alpha: glowOpacity),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ─── 3D Flip Card Implementation ──────────────────────────────────────────────
class _Flip3DWidget extends StatefulWidget {
  final Widget front;
  final Widget back;
  final Duration duration;
  const _Flip3DWidget({required this.front, required this.back, required this.duration});

  @override
  State<_Flip3DWidget> createState() => _Flip3DWidgetState();
}

class _Flip3DWidgetState extends State<_Flip3DWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        final angle = _controller.value * math.pi * 2;
        final showFront = angle < math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
          child: showFront
              ? widget.front
              : Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: widget.back),
        );
      },
    );
  }
}

// ─── Glitch Implementation ────────────────────────────────────────────────────
class _GlitchWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const _GlitchWidget({required this.child, required this.duration});

  @override
  State<_GlitchWidget> createState() => _GlitchWidgetState();
}

class _GlitchWidgetState extends State<_GlitchWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        final t = _controller.value;
        double dx = 0, dy = 0;
        if (t < 0.1) { dx = -2; dy = 1; }
        else if (t < 0.2) { dx = 2; dy = -1; }
        else if (t < 0.3) { dx = -1; }
        else if (t < 0.6) { dx = 1; dy = 1; }

        return Stack(
          children: [
            Transform.translate(
              offset: Offset(dx, dy),
              child: widget.child,
            ),
            if (t < 0.1 || t > 0.55 && t < 0.65)
              Transform.translate(
                offset: Offset(dx + 2, dy),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(MakawEffects.accentPink..withValues(alpha: 0.3), BlendMode.screen),
                  child: widget.child,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Typewriter Implementation ────────────────────────────────────────────────
class _TypewriterWidget extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration duration;
  final bool showCursor;
  const _TypewriterWidget({
    required this.text,
    required this.style,
    required this.duration,
    required this.showCursor,
  });

  @override
  State<_TypewriterWidget> createState() => _TypewriterWidgetState();
}

class _TypewriterWidgetState extends State<_TypewriterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..forward();
    _cursorController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); _cursorController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _cursorController]),
      builder: (ctx, child) {
        final charsToShow = (widget.text.length * _controller.value).floor();
        final visibleText = widget.text.substring(0, charsToShow);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(visibleText, style: widget.style),
            if (widget.showCursor)
              Opacity(
                opacity: _cursorController.value < 0.5 ? 1.0 : 0.0,
                child: Text('|', style: widget.style),
              ),
          ],
        );
      },
    );
  }
}

// ─── Aurora Orbit Implementation ──────────────────────────────────────────────
class _AuroraOrbitWidget extends StatefulWidget {
  final Widget child;
  final double orbitRadius;
  final double orbit2Radius;
  final Color orbitColor;
  final Color orbit2Color;
  const _AuroraOrbitWidget({
    required this.child,
    required this.orbitRadius,
    required this.orbit2Radius,
    required this.orbitColor,
    required this.orbit2Color,
  });

  @override
  State<_AuroraOrbitWidget> createState() => _AuroraOrbitWidgetState();
}

class _AuroraOrbitWidgetState extends State<_AuroraOrbitWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        final t = _controller.value;
        final angle1 = t * 2 * math.pi;
        final angle2 = -t * 2 * math.pi;
        final breathe = 1.0 + 0.08 * (math.sin(t * 2 * math.pi));
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: breathe,
              child: widget.child,
            ),
            Positioned(
              left: 0.5 + math.cos(angle1) * (widget.orbitRadius / 150) - 0.02,
              top: 0.5 + math.sin(angle1) * (widget.orbitRadius / 150) - 0.02,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.orbitColor,
                  boxShadow: [BoxShadow(color: widget.orbitColor..withValues(alpha: 0.6), blurRadius: 8)],
                ),
              ),
            ),
            Positioned(
              left: 0.5 + math.cos(angle2) * (widget.orbit2Radius / 150) - 0.015,
              top: 0.5 + math.sin(angle2) * (widget.orbit2Radius / 150) - 0.015,
              child: Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.orbit2Color,
                  boxShadow: [BoxShadow(color: widget.orbit2Color..withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Loading Ring Implementation ──────────────────────────────────────────────
class _LoadingRingWidget extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color color;
  const _LoadingRingWidget({required this.size, required this.strokeWidth, required this.color});

  @override
  State<_LoadingRingWidget> createState() => _LoadingRingWidgetState();
}

class _LoadingRingWidgetState extends State<_LoadingRingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: _controller.value,
              color: widget.color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  _RingPainter({required this.progress, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: 0.08),
    );

    // Animated arc
    final sweepAngle = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + sweepAngle,
          colors: [color, color..withValues(alpha: 0.3)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

// ─── Morph Feather Implementation ─────────────────────────────────────────────
class _MorphFeatherWidget extends StatefulWidget {
  final Widget a;
  final Widget b;
  final Duration duration;
  const _MorphFeatherWidget({required this.a, required this.b, required this.duration});

  @override
  State<_MorphFeatherWidget> createState() => _MorphFeatherWidgetState();
}

class _MorphFeatherWidgetState extends State<_MorphFeatherWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        final t = _controller.value;
        // morphOut: visible 0-0.4, fade out 0.4-0.5, hidden 0.5-0.9, fade in 0.9-1.0
        double opacityA, opacityB;
        double scaleA = 1, scaleB = 1;

        if (t < 0.4) {
          opacityA = 1.0;
          opacityB = 0.0;
          scaleA = 1.0;
        } else if (t < 0.5) {
          final p = (t - 0.4) / 0.1;
          opacityA = 1.0 - p;
          opacityB = p;
          scaleA = 1.0 - p * 0.3;
          scaleB = 0.7 + p * 0.3;
        } else if (t < 0.9) {
          opacityA = 0.0;
          opacityB = 1.0;
          scaleB = 1.0;
        } else {
          final p = (t - 0.9) / 0.1;
          opacityA = p;
          opacityB = 1.0 - p;
          scaleA = 0.7 + p * 0.3;
          scaleB = 1.0 - p * 0.3;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: opacityA,
              child: Transform.scale(scale: scaleA, child: widget.a),
            ),
            Opacity(
              opacity: opacityB,
              child: Transform.scale(scale: scaleB, child: widget.b),
            ),
          ],
        );
      },
    );
  }
}
