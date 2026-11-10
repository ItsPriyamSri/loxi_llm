import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';
import 'prism_art.dart' show RelayPose;

/// Authored 2.5D illustration of the Loki processor die loading a model.
///
/// The whole piece is drawn in the same flat-with-gradient language as the
/// document art: extruded side faces, one top-left light source, elliptical
/// ground shadow, and the mint/peach semantic system (peach = bytes moving,
/// mint = resident). Poses:
///
/// - [RelayPose.idle]     dormant line-art chip, static.
/// - [RelayPose.transfer] peach comet sweeping the die ring, trace pulses.
/// - [RelayPose.loading]  transfer frame plus a warm breathing die glow.
/// - [RelayPose.ready]    resident model — the chip disassembles and
///                        reassembles itself on a slow loop, with a mint
///                        halo, a mint comet lap and a snap flash on seat.
///
/// Reduced motion freezes the clock on the assembled frame; widget tests
/// freeze it the same way.
class ChipArt extends StatefulWidget {
  const ChipArt({super.key, this.pose = RelayPose.idle, this.size = 176});

  final RelayPose pose;
  final double size;

  @override
  State<ChipArt> createState() => _ChipArtState();
}

class _ChipArtState extends State<ChipArt>
    with SingleTickerProviderStateMixin {
  // Widget tests settle with pumpAndSettle, which never returns while a
  // repeating ticker runs. The artwork still renders deterministically.
  static final _inTest = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant ChipArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  void _syncClock() {
    final still = MediaQuery.disableAnimationsOf(context) ||
        _inTest ||
        widget.pose == RelayPose.idle;
    if (still) {
      _clock.stop();
      _clock.value = .12; // assembled resting frame
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 0 = dormant, 1 = energized, 2 = resident. Blended for smooth pose lifts.
    final target = switch (widget.pose) {
      RelayPose.idle => 0.0,
      RelayPose.transfer => 1.0,
      RelayPose.loading => 1.35,
      RelayPose.ready => 2.0,
    };
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: PrismRelay.curve,
          builder: (context, charge, child) => AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _ChipPainter(phase: _clock.value, charge: charge),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter({required this.phase, required this.charge});

  /// Ambient clock, 0..1 repeating.
  final double phase;

  /// 0 dormant → 2 resident. Fractional during pose transitions.
  final double charge;

  static const _side = Color(0xFF1D1A29);
  static const _sideCopper = Color(0xFF59371F);
  static const _faceA = Color(0xFF38344B);
  static const _faceB = Color(0xFF262233);
  static const _pinFaceA = Color(0xFF4C4766);
  static const _pinFaceB = Color(0xFF332F47);
  static const _etchColor = Color(0xFF4E2A10);

  double get _wake => (charge).clamp(0.0, 1.0); // bytes moving / load glow
  double get _ready => (charge - 1).clamp(0.0, 1.0); // resident treatment
  double get _moving => (1 - (charge - 1).clamp(0.0, 1.0)) * _wake;

  /// Explode envelope: assembled hold → snap-out → float → overshoot in →
  /// flash → rest. Scaled by the resident blend so pose transitions ease in.
  double get _explode {
    final p = phase;
    double e;
    if (p < .52) {
      e = 0; // hold assembled (breathing handled separately)
    } else if (p < .66) {
      e = Curves.easeOutCubic.transform((p - .52) / .14);
    } else if (p < .76) {
      e = 1; // exploded hover
      e += math.sin((p - .66) / .10 * math.pi) * .06; // drift
    } else if (p < .90) {
      e = 1 - Curves.easeInOutCubic.transform((p - .76) / .14);
    } else {
      e = 0; // seated; the flash rides on top
    }
    return e * _ready;
  }

  /// Flash 0..1..0 fired as the die seats.
  double get _flash {
    if (phase < .90 || phase > .985) return 0;
    final t = (phase - .90) / .085;
    return math.sin(t * math.pi) * _ready;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);

    final breathing = .62 + .38 * math.sin(phase * 2 * math.pi);
    final explode = _explode;
    final flash = _flash;

    // ---- ground shadows (substrate stays, die shadow shrinks with lift)
    _oval(canvas, const Rect.fromLTWH(30, 166, 140, 17),
        const Color(0x2E171622), 0);
    final dieShadow = Rect.fromLTWH(58 + explode * 4, 164 - explode * 2,
        84 - explode * 8, 12);
    _oval(canvas, dieShadow, Color.lerp(const Color(0x260F0D1A),
        const Color(0x14485A2A), _wake)!, 0);

    // ---- resident halo (mint — mint means ready everywhere else)
    if (_ready > .01) {
      final halo = _ready * (.55 + .45 * breathing);
      canvas.drawCircle(
        const Offset(100, 101),
        88,
        Paint()
          ..shader = RadialGradient(
            colors: [
              PrismRelay.mint.withValues(alpha: .30 * halo),
              PrismRelay.mint.withValues(alpha: .06 * halo),
              PrismRelay.mint.withValues(alpha: 0),
            ],
            stops: const [0, .55, 1],
          ).createShader(const Rect.fromLTWH(12, 13, 176, 176)),
      );
    }

    _drawPins(canvas, explode);
    _drawSubstrate(canvas);
    _drawTraces(canvas, explode);
    _drawDie(canvas, explode, breathing);
    _drawRing(canvas, flash);
    _drawParticles(canvas, flash);
    _drawSparkDots(canvas, explode);

    canvas.restore();
  }

  void _oval(Canvas canvas, Rect rect, Color color, double blur) {
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(rect)
        ..maskFilter = blur > 0
            ? MaskFilter.blur(BlurStyle.normal, blur)
            : null,
    );
  }

  // ---- pins (extruded tabs; slide out as the chip opens) -------------------

  static const _pinSlots = [64.5, 89.0, 113.5, 138.0];

  void _drawPins(Canvas canvas, double explode) {
    const depth = 5.0;
    void pin(Rect face, Offset slide) {
      final shifted = face.shift(slide);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shifted.shift(const Offset(0, depth)),
            const Radius.circular(2.6)),
        Paint()..color = _side,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(shifted, const Radius.circular(2.6)),
        Paint()
          ..shader = LinearGradient(
            begin: face.width > face.height
                ? Alignment.centerLeft
                : Alignment.topCenter,
            end: face.width > face.height
                ? Alignment.centerRight
                : Alignment.bottomCenter,
            colors: const [_pinFaceA, _pinFaceB],
          ).createShader(face),
      );
    }

    for (final y in _pinSlots) {
      pin(Rect.fromLTWH(28, y - 2.5, 14, 5), Offset(-14 * explode, 0));
      pin(Rect.fromLTWH(158, y - 2.5, 14, 5), Offset(14 * explode, 0));
    }
    for (final x in _pinSlots) {
      pin(Rect.fromLTWH(x - 2.5, 30, 5, 14), Offset(0, -13 * explode));
      pin(Rect.fromLTWH(x - 2.5, 156, 5, 14), Offset(0, 13 * explode));
    }
    // Bottom-center "live" pin glows once resident.
    if (_ready > .02) {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          PrismRelay.mint.withValues(alpha: .8 * _ready),
          PrismRelay.mint.withValues(alpha: 0),
        ]).createShader(const Rect.fromLTWH(88, 170, 24, 24));
      canvas.drawCircle(const Offset(100, 176), 9, glow);
    }
  }

  // ---- substrate -------------------------------------------------------------

  void _drawSubstrate(Canvas canvas) {
    const rect = Rect.fromLTWH(40, 44, 120, 120);
    // Extruded side face
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(0, 5)),
          const Radius.circular(17)),
      Paint()..color = _side,
    );
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(17));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_faceA, _faceB],
        ).createShader(rect),
    );
    // Top edge light catch (2.5D key light)
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + 12, rect.top + 1.5)
        ..lineTo(rect.right - 12, rect.top + 1.5),
      Paint()
        ..color = Colors.white.withValues(alpha: .16)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = PrismRelay.periwinkle.withValues(alpha: .30 + .25 * _wake),
    );
    canvas.drawCircle(
        const Offset(52, 57), 2.5, Paint()..color = const Color(0xFF6F6890));
  }

  // ---- traces ----------------------------------------------------------------

  static const _traceLines = [
    (Offset(100, 44), Offset(100, 74)),
    (Offset(100, 164), Offset(100, 134)),
    (Offset(40, 104), Offset(70, 104)),
    (Offset(160, 104), Offset(130, 104)),
  ];

  void _drawTraces(Canvas canvas, double explode) {
    final alpha = .16 + .48 * _wake;
    final paint = Paint()
      ..color = const Color(0xFF8F83C9).withValues(alpha: alpha)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in _traceLines) {
      canvas.drawLine(a, b, paint);
    }
    if (_moving > .02) {
      for (var i = 0; i < _traceLines.length; i++) {
        final t = (phase * 1.6 + i * .25) % 1.0;
        final (a, b) = _traceLines[i];
        final pos = Offset.lerp(a, b, Curves.easeInOut.transform(t))!;
        final fade = math.sin(math.pi * t);
        canvas.drawCircle(
          pos,
          2.4,
          Paint()
            ..color = PrismRelay.peach
                .withValues(alpha: .95 * fade * _moving.clamp(0.0, 1.0))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
        );
      }
    }
  }

  // ---- die --------------------------------------------------------------------

  void _drawDie(Canvas canvas, double explode, double breathing) {
    final lift = explode * 30;
    final rect = Rect.fromLTWH(66, 78, 68, 62).shift(Offset(0, -lift));
    final die = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    // Extrusion side face deepens as the die rises.
    final sideShift = 5.0 + lift * .45;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(Offset(0, sideShift)),
          const Radius.circular(12)),
      Paint()..color = _sideCopper,
    );
    // Separation shadow on the substrate when lifted.
    if (explode > .02) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(66, 78, 68, 62),
            const Radius.circular(12)),
        Paint()
          ..color = const Color(0x40000000)
              .withValues(alpha: .38 * explode),
      );
    }
    final glow = _wake;
    canvas.drawRRect(
      die,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.25, -.3),
          radius: 1.1,
          colors: [
            Color.lerp(const Color(0xFFCFC6EC), const Color(0xFFFFE9BF), glow)!,
            Color.lerp(const Color(0xFF8B7BD0), PrismRelay.peach, glow)!,
            Color.lerp(const Color(0xFF50446E), const Color(0xFFCE8242), glow)!,
          ],
          stops: const [0, .56, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(3.5), const Radius.circular(9)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..color = const Color(0x59FFF4E0),
    );
    // Top-edge light catch on the die itself
    if (glow > .05) {
      canvas.drawPath(
        Path()
          ..moveTo(rect.left + 10, rect.top + 1.2)
          ..lineTo(rect.right - 10, rect.top + 1.2),
        Paint()
          ..color = Colors.white.withValues(alpha: .35 * glow)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
    _etch(canvas, 'LOKI', 100, rect.center.dy - 2, 15.5, FontWeight.w800, 2.6,
        _etchColor.withValues(alpha: .8));
    _etch(canvas, 'L L M', 100, rect.center.dy + 12, 6.2, FontWeight.w700, 3.2,
        _etchColor.withValues(alpha: .6));
    canvas.drawCircle(Offset(rect.left + 10, rect.top + 8), 1.8,
        Paint()..color = _etchColor.withValues(alpha: .65));

    // Warm breathing bloom over a resident die.
    if (_ready > .02) {
      final bloom = _ready * (.5 + .5 * breathing);
      canvas.drawCircle(
        Offset(100, rect.center.dy),
        34,
        Paint()
          ..shader = RadialGradient(colors: [
            PrismRelay.peach.withValues(alpha: .35 * bloom),
            PrismRelay.peach.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: Offset(100, rect.center.dy), radius: 34)),
      );
    }
  }

  void _etch(Canvas canvas, String text, double x, double y, double size,
      FontWeight weight, double letterSpacing, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: PrismRelay.fontFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(x - painter.width / 2, y - painter.height / 2));
  }

  // ---- ring -------------------------------------------------------------------

  void _drawRing(Canvas canvas, double flash) {
    const center = Offset(100, 109);
    const radius = 47.0;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final dim = (.16 + .30 * _wake).clamp(0.0, .5);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF8F83C9).withValues(alpha: dim),
    );
    if (_moving > .02 && flash == 0) {
      // Bytes moving: peach comet.
      canvas.drawArc(
        bounds,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: phase * 2 * math.pi,
            endAngle: phase * 2 * math.pi + 1.15,
            colors: const [Colors.transparent, PrismRelay.peach],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(bounds),
      );
    } else if (_ready > .02) {
      // Resident: mint hairline ring + slow mint comet; flares on seat.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = PrismRelay.mint
              .withValues(alpha: (.5 + .3 * flash).clamp(0.0, 1.0) * _ready),
      );
      final lapPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 4 * flash
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: phase * 2 * math.pi,
          endAngle: phase * 2 * math.pi + .8,
          colors: const [Colors.transparent, Color(0xFFD8F5E4)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(bounds);
      canvas.drawArc(bounds, 0, 2 * math.pi, false, lapPaint);
    }
  }

  // ---- particles ----------------------------------------------------------------

  void _drawParticles(Canvas canvas, double flash) {
    if (flash <= .02) return;
    final rand = math.Random(7);
    for (var i = 0; i < 7; i++) {
      final angle = (rand.nextDouble() - .5) * 1.6;
      final speed = 34 + rand.nextDouble() * 30;
      final dir = Offset(math.sin(angle), -math.cos(angle));
      final pos = const Offset(100, 96) + dir * speed * flash;
      canvas.drawCircle(
        pos,
        1.6 + rand.nextDouble() * 1.4,
        Paint()
          ..color = PrismRelay.mint.withValues(alpha: .85 * (1 - flash))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
    }
  }

  void _drawSparkDots(Canvas canvas, double explode) {
    // Signature accent dots from the document art, bobbing with the lift.
    final bob = math.sin(phase * 2 * math.pi) * 1.5;
    canvas.drawCircle(const Offset(40, 77), 2.7,
        Paint()..color = PrismRelay.peach.withValues(alpha: .35 + .6 * _wake));
    canvas.drawCircle(Offset(161, 60 + bob * .5 + explode * -3), 2.3,
        Paint()..color = PrismRelay.periwinkle.withValues(alpha: .5 + .4 * _ready));
  }

  @override
  bool shouldRepaint(_ChipPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.charge != charge;
}
