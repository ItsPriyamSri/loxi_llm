import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/conversation_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/models/presentation/models_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/generation_settings_screen.dart';
import '../../features/settings/presentation/prompt_library_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../logging/log_viewer_screen.dart';
import '../logging/model_io_log_screen.dart';
import '../providers/shared_preferences_provider.dart';
import '../widgets/prism_dock.dart';
import '../theme/prism_relay.dart';

part 'app_router.g.dart';

/// Shared transition for pushed surfaces: a soft fade with a short
/// directional drift. Reduced-motion users get the page with no movement.
CustomTransitionPage<void> _pushPage(
  GoRouterState state,
  Widget child, {
  Offset begin = const Offset(0, 0.045),
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 210),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: curved, curve: const Interval(0, .75)),
        child: SlideTransition(
          position: Tween(begin: begin, end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final sawOnboarding = prefs.getBool('onboarding_complete') ?? false;

  return GoRouter(
    initialLocation: sawOnboarding ? '/models' : '/onboarding',
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page unavailable')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go(
            prefs.getBool('onboarding_complete') == true
                ? '/models'
                : '/onboarding',
          ),
          child: const Text('Return to Loki'),
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _pushPage(state, const OnboardingScreen(), begin: Offset.zero),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _pushPage(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/generation',
        pageBuilder: (context, state) =>
            _pushPage(state, const GenerationSettingsScreen()),
      ),
      GoRoute(
        path: '/prompts',
        pageBuilder: (context, state) =>
            _pushPage(state, const PromptLibraryScreen()),
      ),
      GoRoute(
        path: '/logs',
        pageBuilder: (context, state) => _pushPage(state, const LogViewerScreen()),
      ),
      GoRoute(
        path: '/model-io',
        pageBuilder: (context, state) =>
            _pushPage(state, const ModelIoLogScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/models',
                builder: (context, state) => const ModelsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (context, state) => const ChatScreen(),
                routes: [
                  GoRoute(
                    path: ':conversationId',
                    pageBuilder: (context, state) => _pushPage(
                          state,
                          ConversationScreen(
                            conversationId:
                                state.pathParameters['conversationId']!,
                          ),
                          begin: const Offset(0.12, 0),
                        ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/documents',
                builder: (context, state) => const DocumentsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _ScaffoldWithNavBar extends StatelessWidget {
  const _ScaffoldWithNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrismRelay.canvas,
      body: navigationShell,
      bottomNavigationBar: PrismDock(
        selectedIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
