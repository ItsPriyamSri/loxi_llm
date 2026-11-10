import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/prism_relay.dart';
import 'prism_icon.dart';

/// Floating three-slot dock. Sits above the canvas with no bar behind it;
/// the pill itself carries the border and shadow.
class PrismDock extends StatelessWidget {
  const PrismDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    (label: 'Models', icon: PrismGlyph.models),
    (label: 'Chat', icon: PrismGlyph.chat),
    (label: 'Documents', icon: PrismGlyph.file),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Material(
        key: const ValueKey('prism-dock'),
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: PrismRelay.surface.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: PrismRelay.lineStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22383743),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
              BoxShadow(
                color: Color(0x10383743),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : PrismRelay.dockMotion,
                    curve: PrismRelay.curve,
                    alignment:
                        AlignmentDirectional(selectedIndex - 1.0, 0),
                    child: const FractionallySizedBox(
                      widthFactor: 1 / 3,
                      heightFactor: 1,
                      child: DecoratedBox(
                        key: ValueKey('prism-dock-selection'),
                        decoration: BoxDecoration(
                          color: PrismRelay.lilacSoft,
                          borderRadius: BorderRadius.all(Radius.circular(21)),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (final (index, destination) in _destinations.indexed)
                      Expanded(
                        child: Semantics(
                          selected: index == selectedIndex,
                          button: true,
                          label: destination.label,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(21),
                            onTap: () {
                              Haptics.selection();
                              onSelected(index);
                            },
                            child: ExcludeSemantics(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 5),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PrismIcon(
                                        destination.icon,
                                        size: 18,
                                        color: index == selectedIndex
                                            ? PrismRelay.plum
                                            : PrismRelay.inkMuted,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        destination.label,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: .2,
                                              color: index == selectedIndex
                                                  ? PrismRelay.plum
                                                  : PrismRelay.inkMuted,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
