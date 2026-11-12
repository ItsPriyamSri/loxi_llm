import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loki_llm/core/providers/download_provider.dart';
import 'package:loki_llm/core/services/download_service.dart';
import 'package:loki_llm/core/services/file_storage_service.dart';
import 'package:loki_llm/core/theme/prism_relay.dart';
import 'package:loki_llm/features/models/domain/model.dart';
import 'package:loki_llm/features/models/domain/model_status.dart';
import 'package:loki_llm/features/models/presentation/models_notifier.dart';
import 'package:loki_llm/features/models/presentation/models_screen.dart';

void main() {
  testWidgets('selecting another model updates the hero without downloading', (
    tester,
  ) async {
    final models = _Catalog();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [modelsNotifierProvider.overrideWith(() => models)],
        child: const MaterialApp(home: ModelsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final hero = find.byKey(const ValueKey('model-hero'));
    expect(find.descendant(of: hero, matching: find.text('Starter')),
        findsOneWidget);
    await tester.tap(find.text('Second model'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: hero, matching: find.text('Second model')),
        findsOneWidget);
    expect(models.requested, isEmpty);
    await tester
        .tap(find.descendant(of: hero, matching: find.text('Download model')));
    expect(models.requested, ['second']);
  });
  testWidgets('loading overlay follows the model state', (tester) async {
    final models = _Catalog();
    await tester.pumpWidget(ProviderScope(
      overrides: [modelsNotifierProvider.overrideWith(() => models)],
      child: MaterialApp(theme: PrismRelay.light, home: const ModelsScreen()),
    ));
    await tester.pumpAndSettle();
    models.setStatus('gemma3-270m-it', ModelStatus.loading);
    await tester.pump();
    expect(find.text('Loading Starter…'), findsOneWidget);
    models.setStatus('gemma3-270m-it', ModelStatus.loaded);
    await tester.pump();
    expect(find.text('Loading Starter…'), findsNothing);
  });

  testWidgets('live transfer changes stay scoped to the selected model',
      (tester) async {
    final models = _Catalog();
    final downloads = _LiveDownloads();
    addTearDown(downloads.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelsNotifierProvider.overrideWith(() => models),
          downloadServiceProvider.overrideWith((_) => downloads),
        ],
        child: MaterialApp(theme: PrismRelay.light, home: const ModelsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    downloads.live.addAll(['gemma3-270m-it', 'second']);
    models.transfer('gemma3-270m-it', .15);
    models.transfer('second', .62);
    await tester.pumpAndSettle();
    final hero = find.byKey(const ValueKey('model-hero'));
    Finder heroText(String text) => find.descendant(
        of: hero, matching: find.textContaining(text));
    expect(heroText('15%'), findsOneWidget);
    await tester.tap(find.text('Second model'));
    await tester.pumpAndSettle();
    expect(heroText('62%'), findsOneWidget);

    models.transfer('gemma3-270m-it', .4);
    await tester.pumpAndSettle();
    expect(heroText('62%'), findsOneWidget);
    expect(heroText('40%'), findsNothing);
    await tester.tap(heroText('Stop download'));
    expect(models.cancelled, ['second']);
  });

  testWidgets('a failed load keeps its reason in the hero', (tester) async {
    final models = _Catalog();
    await tester.pumpWidget(ProviderScope(
      overrides: [modelsNotifierProvider.overrideWith(() => models)],
      child: MaterialApp(theme: PrismRelay.light, home: const ModelsScreen()),
    ));
    await tester.pumpAndSettle();
    models.setStatus('gemma3-270m-it', ModelStatus.downloaded,
        localPath: '/tmp/starter.gguf');
    await tester.pumpAndSettle();

    final hero = find.byKey(const ValueKey('model-hero'));
    await tester
        .tap(find.descendant(of: hero, matching: find.text('Load model')));
    await tester.pumpAndSettle();

    expect(find.descendant(of: hero, matching: find.text('Could not load model')),
        findsOneWidget);
    expect(
        find.descendant(of: hero, matching: find.text('Not enough memory')),
        findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Retry load')),
        findsOneWidget);
  });
}

class _Catalog extends ModelsNotifier {
  final requested = <String>[];
  final cancelled = <String>[];

  void setStatus(String id, ModelStatus status, {String? localPath}) {
    state = AsyncData([
      for (final model in state.requireValue)
        if (model.id == id)
          model.copyWith(
              status: status, localPath: localPath ?? model.localPath)
        else
          model,
    ]);
  }

  @override
  Future<void> loadModel(String modelId) async {
    setStatus(modelId, ModelStatus.error);
    throw StateError('Not enough memory');
  }

  void transfer(String id, double progress) {
    state = AsyncData([
      for (final model in state.requireValue)
        if (model.id == id)
          model.copyWith(
              status: ModelStatus.downloading, downloadProgress: progress)
        else
          model,
    ]);
  }

  @override
  void cancelDownload(String id) => cancelled.add(id);

  @override
  Future<List<Model>> build() async => const [
        Model(
            id: 'gemma3-270m-it',
            name: 'Starter',
            sizeLabel: '253 MB',
            sizeBytes: 253),
        Model(
            id: 'second',
            name: 'Second model',
            sizeLabel: '1 GB',
            sizeBytes: 1000),
      ];

  @override
  Future<void> downloadModel(String modelId) async => requested.add(modelId);
}

class _LiveDownloads extends DownloadService {
  _LiveDownloads() : this._(Dio());
  _LiveDownloads._(this._client) : super(_client, FileStorageService());

  final Dio _client;
  final live = <String>{};

  @override
  bool isDownloading(String modelId) => live.contains(modelId);

  void close() => _client.close();
}
