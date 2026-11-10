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
    final heroLoaded = item?.status == ModelStatus.loaded;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: loading ? null : () => context.push('/settings'),
            icon: const PrismIcon(PrismGlyph.settings,
                size: 22, color: PrismRelay.plum),
            style: IconButton.styleFrom(
              backgroundColor: PrismRelay.lilacSoft,
              minimumSize: const Size.square(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            if (item != null)
              PrismHero(
                key: const ValueKey('model-hero'),
                variant: heroLoaded
                    ? PrismHeroVariant.mint
                    : PrismHeroVariant.violet,
                pose: item.pose,
                status: _focusedId == null &&
                        item.model.id == 'gemma3-270m-it' &&
                        item.status == ModelStatus.available
                    ? 'Suggested starter'
                    : item.label,
                statusGlyph: item.statusGlyph,
                announceStatus: !item.live,
                title: item.model.name,
                detail: Text(item.metadata),
                progress: item.live || item.status == ModelStatus.loading
                    ? _HeroProgress(
                        key: ValueKey(item.model.id), value: item.fraction)
                    : null,
                actionLabel: item.status == ModelStatus.loading
                    ? 'Loading model'
                    : item.status == ModelStatus.loaded
                        ? 'Start a chat'
                        : item.actionLabel,
                actionGlyph: item.status == ModelStatus.loading
                    ? PrismGlyph.relay
                    : item.status == ModelStatus.loaded
                        ? PrismGlyph.chat
                        : item.actionIcon,
                actionEnabled: item.status == ModelStatus.loading
                    ? false
                    : item.status == ModelStatus.loaded
                        ? !loading && !_unloading
                        : actionFor(item) != null,
                onAction: item.status == ModelStatus.loaded
                    ? () => _startChat(item.model)
                    : actionFor(item),
              ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Model library',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: loading || _choosingFile ? null : _sideload,
                  icon: const PrismIcon(PrismGlyph.plus, size: 19),
                  label: Text(_choosingFile ? 'Opening…' : 'Import model'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (catalog.isLoading && models.isEmpty)
              ...const [
                _SkeletonRow(),
                _SkeletonRow(),
                _SkeletonRow(),
              ]
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
                    Text('No models yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Download the starter model above, or import your own.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: loading || _choosingFile ? null : _sideload,
                      icon: const PrismIcon(PrismGlyph.plus, size: 18),
                      label: Text(_choosingFile ? 'Opening…' : 'Import model'),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  const Divider(height: 1),
                  for (var index = 0; index < models.length; index++) ...[
                    _ModelRow(
                      index: index,
                      item: presentation(models[index]),
                      selected: models[index].id == selected?.id,
                      onSelect: loading
                          ? null
                          : () {
                              Haptics.selection();
                              setState(() => _focusedId = models[index].id);
                            },
                      onAction: actionFor(presentation(models[index])),
                    ),
                    if (index != models.length - 1)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: 58),
                        child: Divider(height: 1),
                      ),
                  ],
                ],
              ),
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
                  child: ChipArt(size: 176, pose: RelayPose.loading),
                ),
                const SizedBox(height: 10),
                Text('Loading $modelName…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Large models take a minute the first time.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Vision models may take a little longer.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PrismRelay.inkMuted),
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    color: PrismRelay.accent,
                    backgroundColor: PrismRelay.lilacSoft,
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
              'Downloading · ${(fraction! * 100).toStringAsFixed(0)}%'
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
        ModelStatus.loaded => PrismGlyph.chat,
      };

  PrismGlyph get statusGlyph => switch (status) {
        ModelStatus.available => PrismGlyph.spark,
        ModelStatus.downloading => PrismGlyph.download,
        ModelStatus.paused => PrismGlyph.download,
        ModelStatus.downloaded => PrismGlyph.check,
        ModelStatus.loading => PrismGlyph.relay,
        ModelStatus.loaded => PrismGlyph.check,
        ModelStatus.error => PrismGlyph.warn,
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
    required this.index,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final int index;
  final _ModelPresentation item;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onAction;

  static const _identityTiles = [
    (Color(0xFFFDEBDD), PrismRelay.amberInk),
    (PrismRelay.skySoft, PrismRelay.skyInk),
    (PrismRelay.mintSurface, PrismRelay.greenInk),
    (PrismRelay.lilacSoft, PrismRelay.plum),
    (PrismRelay.coralSoft, PrismRelay.errorInk),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = item.model;
    // Hue marks state first, identity second: mint = resident, peach = bytes
    // moving, blush = failed; at rest each model keeps its own pastel.
    final (tileBg, tileInk) = switch (item.status) {
      ModelStatus.loaded => (PrismRelay.mintSurface, PrismRelay.greenInk),
      ModelStatus.downloading ||
      ModelStatus.loading ||
      ModelStatus.paused =>
        (PrismRelay.peachSurface, PrismRelay.amberInk),
      ModelStatus.error => (PrismRelay.blush, PrismRelay.errorInk),
      _ when isMultimodalModel(model) =>
        (PrismRelay.lilacSoft, PrismRelay.plum),
      _ => _identityTiles[index % _identityTiles.length],
    };
    final stateColor = switch (item.status) {
      ModelStatus.loaded ||
      ModelStatus.downloaded =>
        PrismRelay.greenInk,
      ModelStatus.error => PrismRelay.errorInk,
      ModelStatus.available =>
        item.model.recommendationBadge != null ? PrismRelay.plum : PrismRelay.amberInk,
      _ => PrismRelay.amberInk,
    };
    final showState = item.status != ModelStatus.available ||
        item.model.recommendationBadge != null;
    return Semantics(
      selected: selected,
      button: true,
      label: model.name,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : PrismRelay.motion,
          curve: PrismRelay.curve,
          decoration: BoxDecoration(
            color: selected ? PrismRelay.lilacSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? PrismRelay.periwinkle : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 11, 6, 11),
          child: Column(
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SizedBox.square(
                      dimension: 42,
                      child: PrismIcon(
                        item.status == ModelStatus.loaded
                            ? PrismGlyph.check
                            : isMultimodalModel(model)
                                ? PrismGlyph.image
                                : model.id.startsWith('sideload-')
                                    ? PrismGlyph.file
                                    : PrismGlyph.relay,
                        color: tileInk,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (showState)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: stateColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: item.status == ModelStatus.loaded
                        ? 'Unload model'
                        : item.actionLabel,
                    onPressed: onAction,
                    icon: PrismIcon(
                      item.status == ModelStatus.loaded
                          ? PrismGlyph.unload
                          : item.actionIcon,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: item.status == ModelStatus.loaded
                          ? PrismRelay.mintSurface
                          : PrismRelay.lilacSoft,
                      foregroundColor: item.status == ModelStatus.loaded
                          ? PrismRelay.greenInk
                          : PrismRelay.plum,
                      minimumSize: const Size.square(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.live)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 54, top: 8),
                  child: _TransferProgress(value: item.fraction),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: PrismRelay.line,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const SizedBox.square(dimension: 42),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBar(widthFactor: .55, height: 13),
                SizedBox(height: 7),
                _SkeletonBar(widthFactor: .38, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: PrismRelay.line,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(height: height),
        ),
      );
}

class _TransferProgress extends StatelessWidget {
  const _TransferProgress({super.key, required this.value, this.onDark = false});

  final double? value;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget indicator(double? fraction) => LinearProgressIndicator(
          value: fraction,
          semanticsLabel:
              fraction == null ? 'In progress' : 'Download progress',
          minHeight: 5,
          borderRadius: BorderRadius.circular(6),
          color: onDark ? PrismRelay.peach : PrismRelay.amberInk,
          backgroundColor:
              onDark ? const Color(0x3DFFFFFF) : PrismRelay.peachSurface,
        );
    if (value == null || reduce) return indicator(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 120),
      builder: (_, progress, __) => indicator(progress),
    );
  }
}

/// The transfer bar rendered inside the violet hero — white track, peach
/// fill, always visible while bytes move.
class _HeroProgress extends _TransferProgress {
  const _HeroProgress({super.key, super.value}) : super(onDark: true);
}
