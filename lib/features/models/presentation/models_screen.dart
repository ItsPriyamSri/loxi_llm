import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/download_provider.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/services/ram_check_service.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/chip_art.dart';
import '../../../core/widgets/prism_art.dart';
import '../../../core/widgets/prism_hero.dart';
import '../../../core/widgets/prism_icon.dart';
import '../../../core/platform/haptics.dart';
import '../../chat/presentation/conversation_list_notifier.dart';
import '../domain/model.dart';
import '../domain/model_status.dart';
import 'models_notifier.dart';

class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  String? _focusedId;
  bool _choosingFile = false;
  bool _confirmingLoad = false;
  bool _unloading = false;
  bool _startingChat = false;
  final _downloadRequests = <String>{};
  final _stoppedDownloads = <String>{};

  Future<void> _sideload() async {
    setState(() => _choosingFile = true);
    final before = ref.read(modelsNotifierProvider).valueOrNull ?? const [];
    try {
      await ref.read(modelsNotifierProvider.notifier).sideloadModel();
      if (!mounted) return;
      final after = await ref.read(modelsNotifierProvider.future);
      if (!mounted) return;
      final oldIds = before.map((model) => model.id).toSet();
      final added = after.where((model) =>
          model.id.startsWith('sideload-') && !oldIds.contains(model.id));
      if (added.isNotEmpty) setState(() => _focusedId = added.last.id);
    } catch (error) {
      if (mounted) {
        _notice(error is FormatException
            ? error.message
            : 'Could not open the model file.');
      }
    } finally {
      if (mounted) setState(() => _choosingFile = false);
    }
  }

  Future<void> _load(Model model) async {
    if (_confirmingLoad) return;
    setState(() => _confirmingLoad = true);
    try {
      if (!await RamCheckService.confirmLoad(context, model: model) ||
          !mounted) {
        return;
      }
      setState(() => _focusedId = model.id);
      Haptics.commit();
      await ref.read(modelsNotifierProvider.notifier).loadModel(model.id);
    } on ModelAlreadyLoadingException catch (error) {
      if (mounted) _notice(error.toString());
    } catch (_) {
      // The inference provider reports the failure on the selected model.
    } finally {
      if (mounted) setState(() => _confirmingLoad = false);
    }
  }

  Future<void> _download(Model model) async {
    if (_downloadRequests.contains(model.id) ||
        ref.read(downloadServiceProvider).isDownloading(model.id)) {
      return;
    }
    setState(() {
      _focusedId = model.id;
      _downloadRequests.add(model.id);
      _stoppedDownloads.remove(model.id);
    });
    Haptics.tap();
    try {
      await ref.read(modelsNotifierProvider.notifier).downloadModel(model.id);
    } catch (_) {
      if (mounted) _notice('Could not start the download.');
    } finally {
      if (mounted) setState(() => _downloadRequests.remove(model.id));
    }
  }

  void _stopDownload(Model model) {
    Haptics.tap();
    ref.read(modelsNotifierProvider.notifier).cancelDownload(model.id);
    setState(() => _stoppedDownloads.add(model.id));
  }

  Future<void> _unload(Model model) async {
    if (_unloading) return;
    setState(() => _unloading = true);
    Haptics.tap();
    try {
      await ref.read(modelsNotifierProvider.notifier).unloadModel(model.id);
    } catch (_) {
      if (mounted) _notice('Could not unload the model.');
    } finally {
      if (mounted) setState(() => _unloading = false);
    }
  }

  void _startChat(Model model) {
    if (_startingChat) return;
    _startingChat = true;
    Haptics.commit();
    try {
      final id = ref
          .read(conversationListNotifierProvider.notifier)
          .createConversation(modelId: model.id);
      context.go('/chat/$id');
    } catch (_) {
      _notice('Could not start a chat.');
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _startingChat = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(modelsNotifierProvider);
    final inference = ref.watch(inferenceNotifierProvider);
    final service = ref.watch(downloadServiceProvider);
    final models = catalog.valueOrNull ?? const <Model>[];
    final notifier = ref.read(modelsNotifierProvider.notifier);
    final loadingModel = loadingModelOf(models);
    final loading = loadingModel != null;
    final ready = inference.asData?.value != null
        ? ref.read(inferenceNotifierProvider.notifier).loadedModel
        : null;
    final selected = loadingModel ??
        models.where((m) => m.id == _focusedId).firstOrNull ??
        models.where((m) => service.isDownloading(m.id)).firstOrNull ??
        models.where((m) => m.id == ready?.id).firstOrNull ??
        models.where((m) => m.id == 'gemma3-270m-it').firstOrNull ??
        models.firstOrNull;

    _ModelPresentation presentation(Model model) {
      final live = service.isDownloading(model.id);
      final isReady = ready?.id == model.id;
      final stopped = _stoppedDownloads.contains(model.id) &&
          !live &&
          (model.status == ModelStatus.available ||
              model.status == ModelStatus.downloading ||
              model.status == ModelStatus.error && model.localPath == null);
      final status = isReady
          ? ModelStatus.loaded
          : stopped
              ? ModelStatus.paused
              : model.status == ModelStatus.loaded
                  ? ModelStatus.downloaded
                  : model.status;
      return _ModelPresentation(
        model: model,
        status: status,
        live: live,
        speed: notifier.downloadSpeed[model.id],
      );
    }

    VoidCallback? actionFor(_ModelPresentation item) {
      if (loading || _confirmingLoad || _unloading) return null;
      final model = item.model;
      if (_downloadRequests.contains(model.id) && !item.live) return null;
      return switch (item.status) {
        ModelStatus.available || ModelStatus.paused => () => _download(model),
        ModelStatus.downloading =>
          item.live ? () => _stopDownload(model) : () => _download(model),
        ModelStatus.downloaded => model.canLoad ? () => _load(model) : null,
        ModelStatus.loading => null,
        ModelStatus.loaded => () => _unload(model),
        ModelStatus.error =>
          model.localPath != null ? () => _load(model) : () => _download(model),
      };
    }

    final item = selected == null ? null : presentation(selected);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            icon: const PrismIcon(PrismGlyph.settings),
            tooltip: 'Settings',
            onPressed: loading ? null : () => context.push('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            if (item != null)
              PrismHero(
                key: const ValueKey('model-hero'),
                title: item.model.name,
                tint: item.tint,
                announceStatus: !item.live,
                pose: item.pose,
                status: _focusedId == null &&
                        item.model.id == 'gemma3-270m-it' &&
                        item.status == ModelStatus.available
                    ? 'Suggested starter'
                    : item.label,
                detail: Text(item.metadata,
                    style: Theme.of(context).textTheme.bodySmall),
                progress: item.live || item.status == ModelStatus.loading
                    ? _TransferProgress(
                        key: ValueKey(item.model.id), value: item.fraction)
                    : null,
                action: FilledButton.icon(
                  onPressed: item.status == ModelStatus.loaded &&
                          !loading &&
                          !_unloading
                      ? () => _startChat(item.model)
                      : actionFor(item),
                  icon: PrismIcon(
                    item.status == ModelStatus.loaded
                        ? PrismGlyph.chat
                        : item.actionIcon,
                    size: 17,
                  ),
                  label: Text(item.status == ModelStatus.loaded
                      ? 'Start a chat'
                      : item.actionLabel),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Model library',
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: loading || _choosingFile ? null : _sideload,
                    icon: const PrismIcon(PrismGlyph.file),
                    label: Text(_choosingFile ? 'Opening…' : 'Import a file'),
                  ),
                ],
              ),
            ),
            if (catalog.isLoading && models.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (catalog.hasError)
              Container(
                decoration: BoxDecoration(
                  color: PrismRelay.blush,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF3C4C4)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    const PrismIcon(PrismGlyph.warn,
                        size: 20, color: PrismRelay.errorInk),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Could not load the model library',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PrismRelay.errorInk, fontSize: 13)),
                    ),
                    IconButton(
                      tooltip: 'Reload model library',
                      icon: const PrismIcon(PrismGlyph.refresh,
                          size: 20, color: PrismRelay.errorInk),
                      onPressed: () => ref.invalidate(modelsNotifierProvider),
                    ),
                  ],
                ),
              )
            else if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 44),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: PrismRelay.lilacSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const SizedBox.square(
                        dimension: 72,
                        child: PrismIcon(PrismGlyph.relay,
                            size: 30, color: PrismRelay.plum),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('No models available',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Download a model above, or import a file.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: loading || _choosingFile ? null : _sideload,
                      icon: const PrismIcon(PrismGlyph.plus, size: 18),
                      label: Text(_choosingFile ? 'Opening…' : 'Import a file'),
                    ),
                  ],
                ),
              ),
            for (final model in models) ...[
              _ModelRow(
                item: presentation(model),
                selected: model.id == selected?.id,
                onSelect: loading
                    ? null
                    : () {
                        Haptics.selection();
                        setState(() => _focusedId = model.id);
                      },
                onAction: actionFor(presentation(model)),
              ),
              const SizedBox(height: PrismRelay.rowGap),
            ],
          ],
        ),
        if (loadingModel != null)
          Positioned.fill(child: _LoadingOverlay(modelName: loadingModel.name)),
      ]),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.modelName});
  final String modelName;

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Semantics(
        liveRegion: true,
        label: 'Loading $modelName into memory',
        child: Container(
          color: PrismRelay.canvas.withValues(alpha: .97),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ExcludeSemantics(
                  child: ChipArt(size: 180, pose: RelayPose.loading),
                ),
                Text('Loading $modelName…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Large models take a minute — it happens once per model.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    color: PrismRelay.amberInk,
                    backgroundColor: PrismRelay.peachSurface,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelPresentation {
  const _ModelPresentation({
    required this.model,
    required this.status,
    required this.live,
    required this.speed,
  });

  final Model model;
  final ModelStatus status;
  final bool live;
  final double? speed;

  double? get fraction => live && model.downloadProgress > 0
      ? model.downloadProgress.clamp(0.0, 1.0)
      : null;

  String get metadata {
    final companion = model.mmprojSizeBytes;
    final inputs = isMultimodalModel(model) ? 'Text and images' : 'Text';
    if (companion != null) {
      final total = model.sizeBytes + companion;
      final label = total >= 1000000000
          ? '${(total / 1000000000).toStringAsFixed(2)} GB'
          : '${(total / 1000000).toStringAsFixed(0)} MB';
      return '$inputs · $label total';
    }
    return '$inputs · ${model.sizeLabel}${isMultimodalModel(model) ? ' + vision file' : ''}';
  }

  String get label => switch (status) {
        ModelStatus.available => model.recommendationBadge ?? 'Available',
        ModelStatus.downloading when !live => 'Download interrupted',
        ModelStatus.downloading => [
            if (fraction != null)
              '${(fraction! * 100).toStringAsFixed(0)}%'
            else
              'Downloading…',
            if (speed != null && speed! > 0)
              speed! >= 1048576
                  ? '${(speed! / 1048576).toStringAsFixed(1)} MB/s'
                  : '${(speed! / 1024).toStringAsFixed(0)} KB/s',
          ].join(' · '),
        ModelStatus.paused => 'Download stopped',
        ModelStatus.downloaded => 'Downloaded',
        ModelStatus.loading => 'Loading into memory…',
        ModelStatus.loaded => 'Ready on this device',
        ModelStatus.error => model.localPath != null
            ? 'Could not load model'
            : 'Could not complete download',
      };

  String get actionLabel => switch (status) {
        ModelStatus.available => 'Download model',
        ModelStatus.downloading when live => 'Stop download',
        ModelStatus.downloading || ModelStatus.paused => 'Download again',
        ModelStatus.downloaded => 'Load model',
        ModelStatus.loading => 'Loading model',
        ModelStatus.loaded => 'Unload model',
        ModelStatus.error =>
          model.localPath != null ? 'Retry load' : 'Retry download',
      };

  PrismGlyph get actionIcon => switch (status) {
        ModelStatus.available => PrismGlyph.download,
        ModelStatus.downloading when live => PrismGlyph.close,
        ModelStatus.downloading ||
        ModelStatus.paused ||
        ModelStatus.error =>
          PrismGlyph.refresh,
        ModelStatus.downloaded => PrismGlyph.play,
        ModelStatus.loading => PrismGlyph.relay,
        ModelStatus.loaded => PrismGlyph.unload,
      };

  Color get tint => switch (status) {
        ModelStatus.loaded => PrismRelay.mintSurface,
        ModelStatus.error => PrismRelay.blush,
        ModelStatus.downloading ||
        ModelStatus.loading ||
        ModelStatus.paused =>
          PrismRelay.peachSurface,
        _ => PrismRelay.lilacSoft,
      };

  RelayPose get pose => switch (status) {
        ModelStatus.loaded => RelayPose.ready,
        ModelStatus.loading => RelayPose.loading,
        ModelStatus.downloading when live => RelayPose.transfer,
        _ => RelayPose.idle,
      };
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final _ModelPresentation item;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = item.model;
    // Motion hue is reserved for state, never for identity: one violet tile
    // family at rest, mint when resident, peach while bytes move, blush on
    // failure. Identity glyphs only distinguish capability (image / file).
    final (glyph, tint, ink) = switch (item.status) {
      ModelStatus.loaded => (
          PrismGlyph.check,
          PrismRelay.mintSurface,
          PrismRelay.greenInk
        ),
      ModelStatus.downloading ||
      ModelStatus.loading ||
      ModelStatus.paused =>
        (PrismGlyph.download, PrismRelay.peachSurface, PrismRelay.amberInk),
      ModelStatus.error => (
          PrismGlyph.warn,
          PrismRelay.blush,
          PrismRelay.errorInk
        ),
      _ when isMultimodalModel(model) => (
          PrismGlyph.image,
          PrismRelay.lilacSoft,
          PrismRelay.plum
        ),
      _ when model.id.startsWith('sideload-') => (
          PrismGlyph.file,
          PrismRelay.lilacSoft,
          PrismRelay.plum
        ),
      _ => (PrismGlyph.relay, PrismRelay.lilacSoft, PrismRelay.plum),
    };
    final color = item.status == ModelStatus.loaded ? PrismRelay.greenInk : ink;
    return Card(
      color: selected ? PrismRelay.lilacSoft : PrismRelay.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? PrismRelay.periwinkle.withValues(alpha: .8)
              : PrismRelay.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            selected: selected,
            onTap: onSelect,
            leading: DecoratedBox(
              decoration: BoxDecoration(
                color: item.status == ModelStatus.loaded
                    ? PrismRelay.mintSurface
                    : tint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: SizedBox.square(
                dimension: 38,
                child: PrismIcon(
                  item.status == ModelStatus.loaded ? PrismGlyph.check : glyph,
                  color: color,
                  size: 18,
                ),
              ),
            ),
            title: Text(item.model.name, style: theme.textTheme.titleSmall),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.metadata, style: theme.textTheme.bodySmall),
                if (item.status != ModelStatus.available ||
                    item.model.recommendationBadge != null)
                  Text(item.label,
                      style:
                          theme.textTheme.labelMedium?.copyWith(color: color)),
              ],
            ),
            trailing: IconButton(
              tooltip: item.actionLabel,
              onPressed: onAction,
              icon: PrismIcon(item.actionIcon),
            ),
          ),
          if (item.live)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _TransferProgress(value: item.fraction),
            ),
        ],
      ),
    );
  }
}

class _TransferProgress extends StatelessWidget {
  const _TransferProgress({super.key, this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce && value == null) {
      return const SizedBox(
          height: 5,
          width: double.infinity,
          child: ColoredBox(color: PrismRelay.peach));
    }
    Widget indicator(double? fraction) => LinearProgressIndicator(
          value: fraction,
          semanticsLabel:
              fraction == null ? 'In progress' : 'Download progress',
          minHeight: 5,
          borderRadius: BorderRadius.circular(6),
          color: PrismRelay.amberInk,
          backgroundColor: PrismRelay.peach,
        );
    if (value == null || reduce) return indicator(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 120),
      builder: (_, progress, __) => indicator(progress),
    );
  }
}
