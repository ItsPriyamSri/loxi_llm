import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_blocks.dart';
import '../../../core/widgets/prism_icon.dart';
import '../domain/generation_settings.dart';
import 'settings_notifier.dart';

class GenerationSettingsScreen extends ConsumerWidget {
  const GenerationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsNotifierProvider);
    final inference = ref.watch(inferenceNotifierProvider);
    final backend = inference.asData?.value;
    final model = backend == null
        ? null
        : ref.read(inferenceNotifierProvider.notifier).loadedModel;
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final settings = model == null ? null : notifier.generationFor(model.id);
    final loadedThreads = backend?.generationParams['nThreads'];
    final loadedContext = backend?.generationParams['contextSize'];
    final loadedBatch = backend?.generationParams['batchSize'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generation'),
      ),
      body: model == null || settings == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              children: [
                PrismNotice(
                  message: inference.isLoading
                      ? 'Loading model…'
                      : inference.hasError
                          ? 'Could not load model'
                          : 'Load a model to edit its settings',
                  failed: inference.hasError,
                  actionLabel: !inference.isLoading &&
                          GoRouter.maybeOf(context) != null
                      ? 'Models'
                      : null,
                  onAction: () => context.go('/models'),
                ),
              ],
            )
          : _Sliders(
              modelId: model.id,
              modelName: model.name,
              loadedContext: loadedContext is int ? loadedContext : 2048,
              settings: settings,
              onChanged: (next) {
                final before = loadedThreads is int &&
                    loadedContext is int &&
                    loadedBatch is int &&
                    settings.differsFromLoaded(
                      nThreads: loadedThreads,
                      contextSize: loadedContext,
                      batchSize: loadedBatch,
                    );
                notifier.saveGeneration(model.id, next);
                final after = loadedThreads is int &&
                    loadedContext is int &&
                    loadedBatch is int &&
                    next.clamped().differsFromLoaded(
                          nThreads: loadedThreads,
                          contextSize: loadedContext,
                          batchSize: loadedBatch,
                        );
                if (!before && after && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Reload the model to use the new threads, context, or batch size.',
                      ),
                    ),
                  );
                }
              },
            ),
    );
  }
}

class _Sliders extends StatelessWidget {
  const _Sliders({
    required this.modelId,
    required this.modelName,
    required this.loadedContext,
    required this.settings,
    required this.onChanged,
  });

  final String modelId;
  final String modelName;
  final int loadedContext;
  final GenerationSettings settings;
  final ValueChanged<GenerationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final replyLength = settings.maxTokensForLoadedContext(loadedContext);
    final maxTokensLimit = loadedContext - GenerationSettings.promptRoom;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Card(
          color: PrismRelay.lilacSoft,
          child: ListTile(
              leading: const PrismIcon(PrismGlyph.relay, color: PrismRelay.plum),
              title: Text(modelName)),
        ),
        const PrismSectionHeader('Next message',
            padding: EdgeInsets.fromLTRB(0, 24, 0, 4)),
        Text(
          'Used on the next reply, including a tool-using turn.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _slider(
          context,
          label: 'Temperature',
          value: settings.temperature,
          min: 0,
          max: 2,
          divisions: 40,
          caption: settings.temperature.toStringAsFixed(2),
          onChanged: (v) => onChanged(settings.copyWith(temperature: v)),
        ),
        _slider(
          context,
          label: 'Reply length',
          value: replyLength.toDouble(),
          min: 64,
          max: maxTokensLimit.toDouble(),
          divisions: (maxTokensLimit - 64) ~/ 64,
          caption: '$replyLength',
          onChanged: (v) => onChanged(settings.copyWith(maxTokens: v.round())),
        ),
        Text(
          'Space for the conversation: ${loadedContext - replyLength} tokens.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _slider(
          context,
          label: 'Top-k',
          value: settings.topK.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          caption: '${settings.topK}',
          onChanged: (v) => onChanged(settings.copyWith(topK: v.round())),
        ),
        _slider(
          context,
          label: 'Top-p',
          value: settings.topP,
          min: 0.05,
          max: 1,
          divisions: 19,
          caption: settings.topP.toStringAsFixed(2),
          onChanged: (v) => onChanged(settings.copyWith(topP: v)),
        ),
        _slider(
          context,
          label: 'Repeat penalty',
          value: settings.repeatPenalty,
          min: 1,
          max: 1.5,
          divisions: 10,
          caption: settings.repeatPenalty.toStringAsFixed(2),
          onChanged: (v) => onChanged(settings.copyWith(repeatPenalty: v)),
        ),
        const PrismSectionHeader('When the model is loaded',
            padding: EdgeInsets.fromLTRB(0, 24, 0, 4)),
        Text(
          'Takes effect the next time this model is loaded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _slider(
          context,
          label: 'Threads',
          value: settings.nThreads.toDouble(),
          min: 1,
          max: 8,
          divisions: 7,
          caption: '${settings.nThreads}',
          onChanged: (v) => onChanged(settings.copyWith(nThreads: v.round())),
        ),
        _choice(
          context,
          label: 'Context size',
          choices: GenerationSettings.contextChoices,
          value: settings.contextSize,
          onChanged: (v) => onChanged(settings.copyWith(contextSize: v)),
        ),
        _choice(
          context,
          label: 'Batch size',
          choices: GenerationSettings.batchChoices,
          value: settings.batchSize,
          onChanged: (v) => onChanged(settings.copyWith(batchSize: v)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () {
              Haptics.tap();
              onChanged(GenerationSettings.defaultsFor(modelId));
            },
            icon: const PrismIcon(PrismGlyph.refresh, size: 18),
            label: const Text('Reset to this model\'s defaults'),
          ),
        ),
      ],
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String caption,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Same label row as the Settings sliders: name left, value right.
        Row(children: [
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.titleSmall)),
          Text(caption,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PrismRelay.accent, fontFeatures: PrismRelay.numbers)),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: caption,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required List<int> choices,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final index = choices.indexOf(value).clamp(0, choices.length - 1);
    return _slider(
      context,
      label: label,
      value: index.toDouble(),
      min: 0,
      max: (choices.length - 1).toDouble(),
      divisions: choices.length - 1,
      caption: '${choices[index]}',
      onChanged: (v) => onChanged(choices[v.round()]),
    );
  }
}
