import 'package:flutter/material.dart';

import '../theme/prism_relay.dart';
import 'chip_art.dart';
import 'prism_art.dart';

class PrismHero extends StatelessWidget {
  const PrismHero({
    super.key,
    required this.title,
    required this.tint,
    this.detail,
    this.status,
    this.announceStatus = true,
    this.progress,
    this.action,
    this.artwork = PrismArtwork.relay,
    this.pose = RelayPose.idle,
  });

  final String title;
  final Color tint;
  final Widget? detail;
  final String? status;
  final bool announceStatus;
  final Widget? progress;
  final Widget? action;
  final PrismArtwork artwork;
  final RelayPose pose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PrismRelay.motion,
      curve: PrismRelay.curve,
      constraints: const BoxConstraints(minHeight: PrismRelay.heroHeight),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.72, -.65),
          radius: 1.3,
          colors: [tint, Color.lerp(tint, PrismRelay.surface, .48)!],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PrismRelay.line),
        boxShadow: PrismRelay.shadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackArt = constraints.maxWidth < 245 ||
              MediaQuery.textScalerOf(context).scale(16) > 23;
          final artSize = stackArt
              ? 86.0
              : (constraints.maxWidth * .40).clamp(92.0, PrismRelay.artStage);
          final art = DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                PrismRelay.surface.withValues(alpha: .65),
                PrismRelay.surface.withValues(alpha: 0),
              ]),
            ),
            child: artwork == PrismArtwork.relay
                ? ChipArt(pose: pose, size: artSize)
                : PrismArt(artwork: artwork, pose: pose, size: artSize),
          );
          final content = ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 170),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (status != null)
                    Semantics(
                      liveRegion: announceStatus,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child:
                            Text(status!, style: theme.textTheme.labelMedium),
                      ),
                    ),
                  if (detail != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 3), child: detail),
                  const Spacer(),
                  SizedBox(
                    height: 14,
                    child: Align(alignment: Alignment.center, child: progress),
                  ),
                  action ?? const SizedBox(height: 48),
                ],
              ),
            ),
          );
          if (stackArt) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(alignment: AlignmentDirectional.centerEnd, child: art),
                content
              ],
            );
          }
          return Row(children: [Expanded(child: content), art]);
        },
      ),
    );
  }
}
