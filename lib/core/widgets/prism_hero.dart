import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';
import 'prism_art.dart';
import 'prism_icon.dart';

/// Which panel treatment a [PrismHero] wears.
///
/// Violet for the model and chat heroes, mint for the document library.
enum PrismHeroVariant { violet, mint }

/// Soft lilac ink for the status and detail lines on the violet panel.
const _onVioletSoft = Color(0xFFEDE6FF);

/// The chip illustration worn by the Models and Chat heroes.
const kChipArt = 'assets/art/tech-chip.png';

/// The shared 200 dp hero tile used on the pages with a hero.
///
/// One radius, one art stage and one action baseline across every instance.
/// The CTA is always a full-width raised button so it reads as the single
/// obvious action of the page.
class PrismHero extends StatelessWidget {
  const PrismHero({
    super.key,
    required this.title,
    this.variant = PrismHeroVariant.violet,
    this.status,
    this.statusGlyph,
    this.detail,
    this.announceStatus = true,
    this.progress,
    this.actionLabel,
    this.actionGlyph,
    this.onAction,
    this.artwork = PrismArtwork.relay,
    this.artImageAsset,
    this.cornerActionLabel,
    this.cornerActionGlyph,
    this.onCornerAction,
  });

  final String title;
  final PrismHeroVariant variant;

  /// Small status line above the title. Rendered verbatim — pass the case
  /// you want ("Ready on this device", or "DOWNLOADING · 38%" for in-flight).
  final String? status;
  final PrismGlyph? statusGlyph;
  final Widget? detail;
  final bool announceStatus;

  /// Reserved 16 dp slot; pass an indicator or leave the space empty.
  final Widget? progress;

  /// Full-width CTA. When [actionLabel] is null the action slot renders
  /// nothing, but its space is kept so the tile does not jump between
  /// states. A null [onAction] shows the action disabled.
  final String? actionLabel;
  final PrismGlyph? actionGlyph;
  final VoidCallback? onAction;

  final PrismArtwork artwork;

  /// Optional raster art (transparent PNG) shown instead of [artwork].
  final String? artImageAsset;

  /// A whisper-of-a-pill pinned to the hero's top right (e.g. "Unload").
  final String? cornerActionLabel;
  final PrismGlyph? cornerActionGlyph;
  final VoidCallback? onCornerAction;

  bool get _dark => variant == PrismHeroVariant.violet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _dark ? Colors.white : PrismRelay.ink;

    final titleStyle = theme.textTheme.headlineLarge!.copyWith(
      fontSize: 22,
      height: 1.1,
      letterSpacing: -0.6,
      color: foreground,
    );
    final statusStyle = theme.textTheme.labelSmall!.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
      color: _dark ? _onVioletSoft : PrismRelay.greenInk,
      fontFeatures: PrismRelay.numbers,
    );

    Widget artFor(double width) => artImageAsset == null
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                PrismRelay.surface.withValues(alpha: .28),
                PrismRelay.surface.withValues(alpha: 0),
              ]),
            ),
            child: PrismArt(artwork: artwork, size: width),
          )
        : Image.asset(
            artImageAsset!,
            width: width,
            height: width,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 172),
      child: IntrinsicHeight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status != null)
              Semantics(
                liveRegion: announceStatus,
                child: Row(
                  children: [
                    if (statusGlyph != null) ...[
                      PrismIcon(statusGlyph!, size: 13, color: statusStyle.color),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        status!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: statusStyle,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.only(top: status == null ? 0 : 10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _dark ? _onVioletSoft : const Color(0xFF31655A),
                  ),
                  child: detail!,
                ),
              ),
            const Spacer(),
            SizedBox(
              height: 14,
              child: Align(alignment: Alignment.center, child: progress),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: actionLabel == null
                  ? const SizedBox.shrink()
                  : _HeroAction(
                      label: actionLabel!,
                      glyph: actionGlyph,
                      variant: variant,
                      enabled: onAction != null,
                      onTap: onAction,
                    ),
            ),
          ],
        ),
      ),
    );

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : PrismRelay.motion,
      curve: PrismRelay.curve,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: PrismRelay.heroHeight),
      decoration: BoxDecoration(
        gradient: switch (variant) {
          PrismHeroVariant.violet => const LinearGradient(
              begin: Alignment(-.72, -1),
              end: Alignment(.78, 1.05),
              colors: PrismRelay.heroViolet,
              stops: [0, .52, 1],
            ),
          PrismHeroVariant.mint => const LinearGradient(
              begin: Alignment(-.72, -1),
              end: Alignment(.82, 1.05),
              colors: [Color(0xFFEAF8F0), Color(0xFFDDF1E6), Color(0xFFD0EBDD)],
            ),
        },
        borderRadius: BorderRadius.circular(22),
        border: _dark ? null : Border.all(color: const Color(0xFFC9E6D6)),
        boxShadow: switch (variant) {
          PrismHeroVariant.violet => const [
              BoxShadow(
                color: Color(0x594B3EC4),
                blurRadius: 30,
                offset: Offset(0, 16),
                spreadRadius: -14,
              ),
              BoxShadow(color: Color(0x2E241B5C), blurRadius: 4, offset: Offset(0, 2)),
            ],
          PrismHeroVariant.mint => const [
              BoxShadow(
                color: Color(0x332D6352),
                blurRadius: 26,
                offset: Offset(0, 14),
                spreadRadius: -14,
              ),
            ],
        },
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Decorative optic flare — static, only on the violet panel.
            if (_dark)
              const Positioned(
                top: -70,
                right: -54,
                child: IgnorePointer(
                  child: _HeroFlare(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // From about 1.2x text the hero stacks so the CTA keeps
                  // the full width instead of truncating beside the art.
                  final bigText = MediaQuery.textScalerOf(context).scale(16) > 19;
                  if (bigText) {
                    // Art sits top-start, clear of the corner pill.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        artFor(88),
                        content,
                      ],
                    );
                  }
                  final artSize =
                      (constraints.maxWidth * .46).clamp(120.0, PrismRelay.artStage);
                  return Row(
                    children: [
                      Expanded(child: content),
                      SizedBox(
                        width: artSize,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: artFor(artSize),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (cornerActionLabel != null)
              Positioned(
                top: 14,
                right: 14,
                child: _CornerPill(
                  label: cornerActionLabel!,
                  glyph: cornerActionGlyph,
                  onTap: onCornerAction,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroFlare extends StatelessWidget {
  const _HeroFlare();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x7A8E7BF0), Color(0x008E7BF0)],
        ),
      ),
      child: SizedBox.square(dimension: 150),
    );
  }
}

/// The hero's raised CTA. The disabled state dims but keeps its 48 dp
/// target.
class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.label,
    required this.variant,
    required this.enabled,
    this.glyph,
    this.onTap,
  });

  final String label;
  final PrismGlyph? glyph;
  final PrismHeroVariant variant;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      PrismHeroVariant.violet => (Colors.white, PrismRelay.violetDeep),
      PrismHeroVariant.mint => (PrismRelay.greenInk, Colors.white),
    };
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduce ? Duration.zero : PrismRelay.motion,
      curve: PrismRelay.curve,
      decoration: BoxDecoration(
        color: enabled ? bg : bg.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: variant == PrismHeroVariant.violet
                      ? const Color(0x47241B5C)
                      : const Color(0x472D6352),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: enabled ? fg : fg.withValues(alpha: .55),
                    ),
                  ),
                ),
                if (glyph != null)
                  PrismIcon(glyph!, size: 19, color: enabled ? fg : fg.withValues(alpha: .55)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The whisper-of-a-pill in the hero's top right — a translucent dark chip
/// with near-white text. Used for quiet secondary actions (e.g. Unload).
class _CornerPill extends StatelessWidget {
  const _CornerPill({
    required this.label,
    this.glyph,
    this.onTap,
  });

  final String label;
  final PrismGlyph? glyph;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: const Color(0x382E1463),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x2EFFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                PrismIcon(glyph!, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The progress bar for the violet hero's progress slot: peach fill on a
/// translucent white track. Indeterminate while [value] is null, and then
/// hidden under reduced motion. A known [value] glides over [glide], so
/// sparse progress updates read as continuous motion.
class PrismHeroProgress extends StatelessWidget {
  const PrismHeroProgress({
    super.key,
    this.value,
    this.semanticsLabel,
    this.glide = Duration.zero,
  });

  final double? value;
  final String? semanticsLabel;
  final Duration glide;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget bar(double? fraction) => LinearProgressIndicator(
          value: fraction,
          semanticsLabel: semanticsLabel,
          minHeight: 5,
          borderRadius: BorderRadius.circular(6),
          color: PrismRelay.peach,
          backgroundColor: const Color(0x3DFFFFFF),
        );
    if (value == null) return reduce ? const SizedBox.shrink() : bar(null);
    if (reduce || glide == Duration.zero) return bar(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: glide,
      builder: (_, fraction, __) => bar(fraction),
    );
  }
}
