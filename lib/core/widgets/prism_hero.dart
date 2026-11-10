import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';
import 'prism_art.dart';
import 'prism_icon.dart';

/// Which panel treatment a [PrismHero] wears.
///
/// Hue means state, not decoration: violet while a model is dormant, in
/// flight or failed, mint when it is resident, plain for neutral panels.
enum PrismHeroVariant { violet, mint, plain }

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
    this.actionEnabled = true,
    this.artwork = PrismArtwork.relay,
    this.pose = RelayPose.idle,
  });

  final String title;
  final PrismHeroVariant variant;

  /// Small caps line above the title. Pair with [statusGlyph].
  final String? status;
  final PrismGlyph? statusGlyph;
  final Widget? detail;
  final bool announceStatus;

  /// Reserved 16 dp slot; pass an indicator or leave the space empty.
  final Widget? progress;

  /// Full-width CTA. When [actionLabel] is null the action slot renders
  /// nothing, but its space is kept so the tile does not jump between
  /// states.
  final String? actionLabel;
  final PrismGlyph? actionGlyph;
  final VoidCallback? onAction;
  final bool actionEnabled;

  final PrismArtwork artwork;
  final RelayPose pose;

  bool get _dark => variant == PrismHeroVariant.violet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final foreground = _dark ? Colors.white : PrismRelay.ink;
    final wash = _dark ? const Color(0xFFFFFFFF) : PrismRelay.surface;

    final titleStyle = theme.textTheme.headlineLarge!.copyWith(
      fontSize: 22,
      height: 1.1,
      letterSpacing: -0.6,
      color: foreground,
    );
    final statusStyle = theme.textTheme.labelSmall!.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.15,
      color: _dark ? const Color(0xFFE4DCFF) : PrismRelay.greenInk,
    );

    Widget artFor(double width) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              wash.withValues(alpha: .28),
              wash.withValues(alpha: 0),
            ]),
          ),
          child: PrismArt(artwork: artwork, pose: pose, size: width),
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
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        status!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: statusStyle,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.only(top: status == null ? 0 : 5),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _dark
                        ? const Color(0xFFEDE7FF)
                        : variant == PrismHeroVariant.mint
                            ? const Color(0xFF31655A)
                            : PrismRelay.inkSecondary,
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
                      enabled: actionEnabled && onAction != null,
                      onTap: onAction,
                    ),
            ),
          ],
        ),
      ),
    );

    final reduce = reduceMotion ? Duration.zero : PrismRelay.motion;
    return AnimatedContainer(
      duration: reduce,
      curve: PrismRelay.curve,
      width: double.infinity,
      height: PrismRelay.heroHeight,
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
          PrismHeroVariant.plain => null,
        },
        color: variant == PrismHeroVariant.plain ? PrismRelay.surface : null,
        borderRadius: BorderRadius.circular(22),
        border: variant == PrismHeroVariant.violet
            ? null
            : Border.all(
                color: variant == PrismHeroVariant.mint
                    ? const Color(0xFFC9E6D6)
                    : PrismRelay.line,
              ),
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
          PrismHeroVariant.plain => PrismRelay.hairline,
        },
      ),
      child: Stack(
        children: [
          // Decorative optic flare — static, only on the violet panel.
          if (_dark && !reduceMotion)
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
                final artSize =
                    (constraints.maxWidth * .42).clamp(112.0, PrismRelay.artStage);
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
        ],
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

/// The hero's white/dark raised CTA. Pressed state dips; disabled state
/// dims ink but keeps its 46 dp target.
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
      PrismHeroVariant.plain => (PrismRelay.accent, Colors.white),
    };
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduce ? Duration.zero : PrismRelay.motion,
      curve: PrismRelay.curve,
      decoration: BoxDecoration(
        color: enabled ? bg : bg.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
        boxShadow: enabled && variant != PrismHeroVariant.plain
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
