import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';
import 'prism_icon.dart';

/// Small uppercase label that opens a group of rows.
class PrismSectionHeader extends StatelessWidget {
  const PrismSectionHeader(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(6, 18, 6, 6),
  });

  final String label;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PrismRelay.inkMuted,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

/// The one error treatment outside dialogs: blush panel, warning glyph,
/// and an optional retry button.
class PrismErrorBanner extends StatelessWidget {
  const PrismErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryTooltip = 'Try again',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryTooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: PrismRelay.blush,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PrismRelay.blushBorder),
        ),
        padding: EdgeInsets.fromLTRB(12, 6, onRetry == null ? 12 : 4, 6),
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const PrismIcon(PrismGlyph.warn,
                size: 20, color: PrismRelay.errorInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PrismRelay.errorInk,
                      fontSize: 13,
                    ),
              ),
            ),
            if (onRetry != null)
              IconButton(
                tooltip: retryTooltip,
                onPressed: onRetry,
                icon: const PrismIcon(PrismGlyph.refresh,
                    size: 20, color: PrismRelay.errorInk),
              ),
          ],
        ),
      ),
    );
  }
}

/// Static backdrop behind the chat list and conversation: a lilac wash
/// top-left and a peach wash bottom-right. Painted once; nothing animates.
class PrismAmbientWash extends StatelessWidget {
  const PrismAmbientWash({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _AmbientPainter(), size: Size.infinite),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.88, -.78),
          radius: 1.3,
          colors: [Color(0x55E9DFFA), Color(0x00E9DFFA)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(1.05, .92),
          radius: 1.3,
          colors: [Color(0x3BFDEBDD), Color(0x00FDEBDD)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
