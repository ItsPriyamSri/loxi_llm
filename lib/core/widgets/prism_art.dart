import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';

enum PrismArtwork { relay, document, chat }

enum RelayPose { idle, transfer, loading, ready }

class PrismArt extends StatelessWidget {
  const PrismArt({
    super.key,
    this.artwork = PrismArtwork.relay,
    this.pose = RelayPose.idle,
    this.size = PrismRelay.artStage,
  });

  final PrismArtwork artwork;
  final RelayPose pose;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = switch (pose) {
      RelayPose.idle => 0.0,
      RelayPose.transfer => 1.0,
      RelayPose.loading => .7,
      RelayPose.ready => -1.0,
    };
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : pose == RelayPose.ready
                  ? PrismRelay.seat
                  : PrismRelay.lift,
          curve: PrismRelay.curve,
          builder: (_, position, __) => CustomPaint(
            size: Size.square(size),
            painter: _ArtworkPainter(artwork, position),
          ),
        ),
      ),
    );
  }
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter(this.artwork, this.position);

  final PrismArtwork artwork;
  final double position;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    switch (artwork) {
      case PrismArtwork.relay:
        _relay(canvas);
      case PrismArtwork.document:
        _document(canvas);
      case PrismArtwork.chat:
        _chat(canvas);
    }
    canvas.restore();
  }

  // The plate outlines use the points from the approved SVG.
  void _relay(Canvas canvas) {
    const bounds = Rect.fromLTWH(36, 60, 128, 108);
    canvas.drawOval(
      const Rect.fromLTWH(38, 150, 124, 27),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x18575078), Color(0x00575078)],
        ).createShader(const Rect.fromLTWH(34, 149, 132, 30)),
    );
    _plate(canvas, 122 + position * 18, const Color(0xFF9F90DC),
        const Color(0xFFD9CEF5));
    _plate(canvas, 104 + position * 9, const Color(0xFFB6A7EB),
        const Color(0xFFE8DDFC));
    _plate(canvas, 86, const Color(0xFFFCF8FF), const Color(0xFFC9B8F3));
    canvas.drawPath(_diamond(86, .8), Paint()..color = const Color(0x58AC9BE7));
    canvas.drawPath(_diamond(86, .53), Paint()..color = PrismRelay.plum);
    canvas.drawCircle(
      const Offset(100, 86),
      29,
      Paint()
        ..shader = RadialGradient(
          colors: [
            PrismRelay.peach.withValues(alpha: position < 0 ? .62 : .29),
            PrismRelay.peach.withValues(alpha: 0),
          ],
        ).createShader(const Rect.fromLTWH(71, 57, 58, 58)),
    );
    canvas.drawPath(
      _diamond(86, .34),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0D8), PrismRelay.peach],
        ).createShader(bounds),
    );
    canvas.drawLine(
      const Offset(91, 86),
      const Offset(109, 86),
      Paint()
        ..color = const Color(0xFFFFFAEE)
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
        const Offset(44, 69), 2.6, Paint()..color = PrismRelay.peach);
    canvas.drawCircle(
        const Offset(155, 63), 2.2, Paint()..color = PrismRelay.periwinkle);
  }

  void _plate(Canvas canvas, double center, Color top, Color edge) {
    final path = _diamond(center, 1);
    canvas.drawPath(
      path.shift(const Offset(0, 4)),
      Paint()..color = Color.lerp(edge, PrismRelay.plum, .23)!,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, edge],
        ).createShader(path.getBounds()),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = PrismRelay.surface.withValues(alpha: .68)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  Path _diamond(double center, double scale) => Path()
    ..moveTo(100, center - 26 * scale)
    ..lineTo(100 + 52 * scale, center - 9 * scale)
    ..lineTo(100 + 64 * scale, center)
    ..lineTo(100 + 52 * scale, center + 9 * scale)
    ..lineTo(100, center + 26 * scale)
    ..lineTo(100 - 52 * scale, center + 9 * scale)
    ..lineTo(100 - 64 * scale, center)
    ..lineTo(100 - 52 * scale, center - 9 * scale)
    ..close();

  void _document(Canvas canvas) {
    canvas.drawOval(
      const Rect.fromLTWH(54, 147, 97, 18),
      Paint()..color = const Color(0x182D6352),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(74, 56, 65, 95), const Radius.circular(7)),
      Paint()..color = PrismRelay.mint,
    );
    final page = Path()
      ..moveTo(64, 48)
      ..lineTo(111, 48)
      ..lineTo(130, 67)
      ..lineTo(130, 146)
      ..lineTo(64, 146)
      ..close();
    canvas.drawPath(
        page,
        Paint()
          ..shader = const LinearGradient(
            colors: [PrismRelay.surface, PrismRelay.mintSurface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(page.getBounds()));
    canvas.drawPath(
      Path()
        ..moveTo(111, 48)
        ..lineTo(111, 67)
        ..lineTo(130, 67)
        ..close(),
      Paint()..color = PrismRelay.mint,
    );
    final rule = Paint()
      ..color = PrismRelay.greenInk.withValues(alpha: .58)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(77, 81 + i * 11),
          Offset(i.isEven ? 111 : 118, 81 + i * 11), rule);
    }
    canvas.drawCircle(
        const Offset(117, 132), 4, Paint()..color = PrismRelay.peach);
  }

  void _chat(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(59, 66, 99, 63), const Radius.circular(18)),
      Paint()..color = PrismRelay.lilac,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(42, 52, 101, 63), const Radius.circular(18)),
      Paint()..color = PrismRelay.surface,
    );
    canvas.drawPath(
      Path()
        ..moveTo(52, 103)
        ..lineTo(49, 124)
        ..lineTo(73, 110)
        ..close(),
      Paint()..color = PrismRelay.surface,
    );
    final stroke = Paint()
      ..color = PrismRelay.periwinkle
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(61, 76), const Offset(115, 76), stroke);
    canvas.drawLine(const Offset(61, 91), const Offset(97, 91), stroke);
    canvas.drawCircle(
        const Offset(145, 125), 13, Paint()..color = PrismRelay.mint);
    canvas.drawPath(
      Path()
        ..moveTo(139, 125)
        ..lineTo(143, 129)
        ..lineTo(151, 120),
      Paint()
        ..color = PrismRelay.greenInk
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ArtworkPainter oldDelegate) =>
      artwork != oldDelegate.artwork || position != oldDelegate.position;
}
