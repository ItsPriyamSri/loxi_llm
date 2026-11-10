import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/prism_relay.dart';

/// Semantic glyph names for the app. Each maps to a Lucide icon; the enum
/// keeps call sites stable while the vector art stays in one audited set.
enum PrismGlyph {
  relay,
  models,
  chat,
  file,
  download,
  check,
  settings,
  plus,
  chevron,
  more,
  close,
  copy,
  audio,
  pause,
  play,
  stop,
  tools,
  log,
  trash,
  image,
  book,
  refresh,
  warn,
  clock,
  graph,
  search,
  lock,
  link,
  send,
  spark,
  down,
  brokenImage,
  unload,
}

const _glyphs = <PrismGlyph, IconData>{
  PrismGlyph.relay: LucideIcons.cpu,
  PrismGlyph.models: LucideIcons.layers,
  PrismGlyph.chat: LucideIcons.messageCircle,
  PrismGlyph.file: LucideIcons.fileText,
  PrismGlyph.download: LucideIcons.download,
  PrismGlyph.check: LucideIcons.check,
  PrismGlyph.settings: LucideIcons.settings,
  PrismGlyph.plus: LucideIcons.plus,
  PrismGlyph.chevron: LucideIcons.chevronRight,
  PrismGlyph.more: LucideIcons.ellipsis,
  PrismGlyph.close: LucideIcons.x,
  PrismGlyph.copy: LucideIcons.copy,
  PrismGlyph.audio: LucideIcons.volume2,
  PrismGlyph.pause: LucideIcons.pause,
  PrismGlyph.play: LucideIcons.play,
  PrismGlyph.stop: LucideIcons.square,
  PrismGlyph.tools: LucideIcons.wrench,
  PrismGlyph.log: LucideIcons.scrollText,
  PrismGlyph.trash: LucideIcons.trash2,
  PrismGlyph.image: LucideIcons.image,
  PrismGlyph.book: LucideIcons.bookOpen,
  PrismGlyph.refresh: LucideIcons.rotateCw,
  PrismGlyph.warn: LucideIcons.triangleAlert,
  PrismGlyph.clock: LucideIcons.clock,
  PrismGlyph.graph: LucideIcons.chartLine,
  PrismGlyph.search: LucideIcons.search,
  PrismGlyph.lock: LucideIcons.lock,
  PrismGlyph.link: LucideIcons.link,
  PrismGlyph.send: LucideIcons.arrowUp,
  PrismGlyph.spark: LucideIcons.sparkles,
  PrismGlyph.down: LucideIcons.arrowDown,
  PrismGlyph.brokenImage: LucideIcons.imageOff,
  PrismGlyph.unload: LucideIcons.eject,
};

class PrismIcon extends StatelessWidget {
  const PrismIcon(this.glyph,
      {super.key, this.size, this.color, this.mirror = false});

  final PrismGlyph glyph;
  final double? size;
  final Color? color;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final resolved = (color ??
            theme.color ??
            Theme.of(context).colorScheme.onSurface)
        .withValues(
            alpha: (color?.a ?? theme.color?.a ?? 1) * (theme.opacity ?? 1));
    final icon = Icon(
      _glyphs[glyph]!,
      size: size ?? (theme.size ?? 24).clamp(20.0, 24.0),
      color: resolved,
      semanticLabel: null,
    );
    if (!mirror || Directionality.of(context) != TextDirection.rtl) {
      return icon;
    }
    return Transform.scale(scaleX: -1, child: icon);
  }
}

/// The app's identity: a flat lilac tile carrying the same die motif the
/// live hero draws in 3D — no gradients, no glow, one plum silhouette.
class PrismBrandMark extends StatelessWidget {
  const PrismBrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .30),
          color: PrismRelay.lilacSoft,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            LucideIcons.cpu,
            color: PrismRelay.plum,
            size: size * .60,
          ),
        ),
      ),
    );
  }
}
