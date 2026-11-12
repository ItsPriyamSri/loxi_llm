import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_art.dart';
import '../../../core/widgets/prism_icon.dart';

/// The welcome page. One screen, one action — the app asks nothing before
/// it has shown what it is.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _finishing = false;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Built once: a CurvedAnimation listens to the controller until disposed.
  late final _artWindow = _window(.02, .52);
  late final _copyWindow = _window(.2, .78);
  late final _buttonWindow = _window(.42, 1);

  CurvedAnimation _window(double begin, double end) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else if (!_entrance.isAnimating && _entrance.value == 0) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _artWindow.dispose();
    _copyWindow.dispose();
    _buttonWindow.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    Haptics.commit();
    setState(() => _finishing = true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (!await prefs.setBool('onboarding_complete', true)) {
        throw StateError('Could not save onboarding preference');
      }
      if (mounted) context.go('/models');
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save setup. Try again.')),
      );
    }
  }

  Widget _rise(Animation<double> window, Widget child) => AnimatedBuilder(
        animation: window,
        builder: (context, child) => Opacity(
          opacity: window.value,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - window.value)),
            child: child,
          ),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: PrismRelay.welcomeFace,
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: PrismRelay.welcomeWash,
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: PrismRelay.welcomeWash2,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Row(
                      children: [
                        const PrismBrandMark(size: 34),
                        const SizedBox(width: 10),
                        Text(
                          'Loki LLM',
                          style: type.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final artSize = (constraints.maxHeight * .68)
                            .clamp(170.0, 290.0);
                        return Center(
                          child: _rise(
                            _artWindow,
                            ExcludeSemantics(
                              child: PrismArt(
                                artwork: PrismArtwork.relay,
                                size: artSize,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _rise(
                          _copyWindow,
                          Text(
                            'Your AI, on\nyour device.',
                            style: type.displaySmall?.copyWith(
                              fontSize: 38,
                              height: 1.04,
                              letterSpacing: -1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _rise(
                          _copyWindow,
                          Text(
                            'Download a model once. Then start a conversation, even offline.',
                            style: type.bodyLarge?.copyWith(
                              color: const Color(0xFF54496B),
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _rise(
                      _buttonWindow,
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: PrismRelay.accentGradient,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x665B3BE3),
                                blurRadius: 22,
                                offset: Offset(0, 12),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            borderRadius: BorderRadius.circular(15),
                            child: InkWell(
                              onTap: _finishing ? null : _finish,
                              borderRadius: BorderRadius.circular(15),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _finishing ? 'Just a moment…' : 'Get started',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const PrismIcon(PrismGlyph.send,
                                        size: 20, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
