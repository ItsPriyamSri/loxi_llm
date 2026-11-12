import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loki_llm/core/providers/shared_preferences_provider.dart';
import 'package:loki_llm/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp(SharedPreferences prefs) {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      // Stub destination so context.go('/models') doesn't throw.
      GoRoute(
        path: '/models',
        builder: (_, __) => const Scaffold(body: Text('Models')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    // Match the app theme's classic ripple so page-transition ripples don't
    // load shaders/ink_sparkle.frag (which fails in the 3.41.0 test env).
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
    ),
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('OnboardingScreen — welcome content', () {
    testWidgets('shows the welcome headline', (tester) async {
      await tester.pumpWidget(_buildApp(prefs));
      await tester.pump();

      expect(find.textContaining('Your AI,'), findsOneWidget);
    });

    testWidgets('shows the offline promise copy', (tester) async {
      await tester.pumpWidget(_buildApp(prefs));
      await tester.pump();

      expect(
        find.text(
          'Download a model once. Then start a conversation, even offline.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('offers exactly one action — Get started', (tester) async {
      await tester.pumpWidget(_buildApp(prefs));
      await tester.pump();

      expect(find.text('Get started'), findsOneWidget);
      expect(find.byType(InkWell).hitTestable(), findsOneWidget);
    });
  });

  group('OnboardingScreen — finish flow', () {
    testWidgets('tapping Get started persists onboarding_complete=true',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs));
      await tester.pump();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(prefs.getBool('onboarding_complete'), isTrue);
    });

    testWidgets('tapping Get started navigates to /models', (tester) async {
      await tester.pumpWidget(_buildApp(prefs));
      await tester.pump();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('Models'), findsOneWidget);
    });
  });
}
