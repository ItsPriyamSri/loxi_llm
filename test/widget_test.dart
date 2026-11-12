import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loki_llm/core/providers/objectbox_provider.dart';
import 'package:loki_llm/core/providers/shared_preferences_provider.dart';
import 'package:loki_llm/core/router/app_router.dart';
import 'package:loki_llm/core/theme/prism_relay.dart';
import 'package:loki_llm/core/widgets/prism_dock.dart';
import 'package:loki_llm/features/models/domain/model.dart';
import 'package:loki_llm/features/models/domain/model_status.dart';
import 'package:loki_llm/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MyApp navigation smoke test', () {
    testWidgets('renders 3-tab bottom navigation', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override store with unimplemented stub — ModelsNotifier
            // returns empty list when box is uninitialized in test env.
            objectBoxStoreProvider.overrideWith(
              (ref) => throw UnimplementedError('No store in test'),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MyApp(),
        ),
      );
      // Allow async providers to settle
      await tester.pump();

      expect(find.byKey(const ValueKey('prism-dock')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('prism-dock-selection')), findsOneWidget);
      expect(find.text('Models'), findsAtLeastNWidgets(1));
      expect(find.text('Chat'), findsAtLeastNWidgets(1));
      expect(find.text('Documents'), findsAtLeastNWidgets(1));
    });

    testWidgets('the dock stops growing past 1.3x text', (tester) async {
      Future<double> dockHeight(double scale) async {
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: PrismRelay.light,
            home: Scaffold(
              bottomNavigationBar:
                  PrismDock(selectedIndex: 2, onSelected: (_) {}),
            ),
          ),
        ));
        return tester.getSize(find.byKey(const ValueKey('prism-dock'))).height;
      }

      final atClamp = await dockHeight(1.3);
      expect(await dockHeight(2), atClamp);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every pushed route renders at large text without errors',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        objectBoxStoreProvider
            .overrideWith((_) => throw UnimplementedError('No store in test')),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      await tester.pumpAndSettle();
      final router = container.read(appRouterProvider);
      for (final (route, title) in [
        ('/settings', 'Settings'),
        ('/generation', 'Generation'),
        ('/prompts', 'Prompts'),
        ('/logs', 'Logs (live)'),
        ('/model-io', 'Model I/O log'),
        ('/invalid-route', 'Page unavailable'),
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(find.text(title), findsWidgets, reason: route);
        expect(tester.takeException(), isNull, reason: route);
      }
    });
  });

  testWidgets('Settings shows inline sliders and saves changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      objectBoxStoreProvider
          .overrideWith((_) => throw UnimplementedError('No store in test')),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.text('300'), findsOneWidget);
    tester.widget<Slider>(find.byType(Slider).first).onChanged!(350);
    await tester.pumpAndSettle();
    expect(find.text('350'), findsOneWidget);
    expect(prefs.getInt('settings_chunk_size'), 350);
  });

  group('Model domain', () {
    test('Model.isDownloaded returns true when status is downloaded', () {
      const model = Model(
        id: 'test-1',
        name: 'Test Model',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
        status: ModelStatus.downloaded,
        localPath: '/tmp/test.gguf',
      );
      expect(model.isDownloaded, isTrue);
      expect(model.isDownloading, isFalse);
      expect(model.canLoad, isTrue);
    });

    test('Model.canLoad is false without localPath', () {
      const model = Model(
        id: 'test-2',
        name: 'Test Model',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
        status: ModelStatus.downloaded,
      );
      expect(model.isDownloaded, isTrue);
      expect(model.canLoad, isFalse);
    });

    test('Model.canLoad is true when status is error and localPath is set '
        '(retrying a failed load)', () {
      const model = Model(
        id: 'test-2b',
        name: 'Test Model',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
        status: ModelStatus.error,
        localPath: '/tmp/test.gguf',
      );
      expect(model.canLoad, isTrue);
    });

    test('Model.canLoad is false when status is error and localPath is null '
        '(failed download, nothing to retry-load)', () {
      const model = Model(
        id: 'test-2c',
        name: 'Test Model',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
        status: ModelStatus.error,
      );
      expect(model.canLoad, isFalse);
    });

    test('Model.isDownloading returns true when status is downloading', () {
      const model = Model(
        id: 'test-3',
        name: 'Test Model',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
        status: ModelStatus.downloading,
      );
      expect(model.isDownloading, isTrue);
      expect(model.isDownloaded, isFalse);
    });

    test('Model.copyWith preserves unchanged fields', () {
      const model = Model(
        id: 'test-4',
        name: 'Original Name',
        sizeLabel: '2GB',
        sizeBytes: 2000000000,
      );
      final updated = model.copyWith(name: 'Updated Name');
      expect(updated.name, equals('Updated Name'));
      expect(updated.id, equals('test-4'));
      expect(updated.status, equals(ModelStatus.available));
    });

    test('Model default status is available', () {
      const model = Model(
        id: 'test-5',
        name: 'Test',
        sizeLabel: '1GB',
        sizeBytes: 1000000000,
      );
      expect(model.status, equals(ModelStatus.available));
      expect(model.downloadProgress, equals(0.0));
      expect(model.format, equals('gguf'));
    });
  });
}
