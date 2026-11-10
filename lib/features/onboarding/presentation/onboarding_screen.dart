import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/chip_art.dart';
import '../../../core/widgets/prism_art.dart';
import '../../../core/widgets/prism_icon.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pages = [
    _OnboardingPage(
      artwork: PrismArtwork.relay,
      pose: RelayPose.ready,
      title: 'Welcome to Loki LLM',
      body: 'Private conversations with AI that runs on your phone.',
    ),
    _OnboardingPage(
      artwork: PrismArtwork.relay,
      pose: RelayPose.transfer,
      title: 'Download a Model',
      body:
          'Download or import a model once. After that, Loki answers with no internet at all.',
    ),
    _OnboardingPage(
      artwork: PrismArtwork.document,
      title: 'Chat & Use Documents',
      body: 'Start a conversation or add documents to use in chat.',
    ),
  ];

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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    void moveTo(int page) {
      Haptics.selection();
      if (duration == Duration.zero) {
        _pageController.jumpToPage(page);
      } else {
        _pageController.animateToPage(page,
            duration: duration, curve: PrismRelay.curve);
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: _pages,
              ),
            ),
            Semantics(
              label: 'Page ${_page + 1} of ${_pages.length}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: duration,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? PrismRelay.periwinkle
                            : PrismRelay.lineStrong,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => moveTo(_page - 1),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  FilledButton(
                    onPressed: _finishing
                        ? null
                        : isLast
                            ? _finish
                            : () => moveTo(_page + 1),
                    child: Text(isLast ? 'Get Started' : 'Next'),
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.artwork,
    required this.title,
    required this.body,
    this.pose = RelayPose.idle,
  });

  final PrismArtwork artwork;
  final RelayPose pose;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.65, -.42),
          radius: .85,
          colors: [
            artwork == PrismArtwork.document
                ? PrismRelay.mintSurface
                : PrismRelay.lilacSoft,
            PrismRelay.canvas,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight:
                    (constraints.maxHeight - 48).clamp(0, double.infinity)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PrismBrandMark(size: 29),
                    const SizedBox(width: 9),
                    Text('Loki LLM', style: type.titleSmall),
                  ],
                ),
                Center(
                    child: artwork == PrismArtwork.relay
                        ? ChipArt(pose: pose, size: 208)
                        : PrismArt(artwork: artwork, pose: pose, size: 208)),
                Text(title, style: type.displaySmall),
                const SizedBox(height: 12),
                Text(body, style: type.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
