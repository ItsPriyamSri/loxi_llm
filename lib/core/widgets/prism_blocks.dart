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

/// Centered empty-library message: a lilac glyph tile, a title, one line
/// of help and an optional call to action.
class PrismEmptyState extends StatelessWidget {
  const PrismEmptyState({
    super.key,
    required this.glyph,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final PrismGlyph glyph;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 44, 32, 0),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: PrismRelay.lilacSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox.square(
              dimension: 72,
              child: PrismIcon(glyph, size: 30, color: PrismRelay.plum),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: type.titleMedium),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: type.bodyMedium?.copyWith(color: PrismRelay.inkMuted),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const PrismIcon(PrismGlyph.plus, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks before a destructive action. True only when the user confirms.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
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
