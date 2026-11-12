import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/download_provider.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/services/ram_check_service.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_blocks.dart';
import '../../../core/widgets/prism_hero.dart';
import '../../../core/widgets/prism_icon.dart';
import '../../../core/platform/haptics.dart';
import '../../chat/presentation/conversation_list_notifier.dart';
import '../data/model_catalog.dart';
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

  /// Why the last load in this session failed, shown in the hero while
  /// that model still reads "Could not load model".
  ({String modelId, String reason})? _loadFailure;
  final _downloadRequests = <String>{};

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
      setState(() {
        _focusedId = model.id;
        _loadFailure = null;
      });
      Haptics.commit();
      await ref.read(modelsNotifierProvider.notifier).loadModel(model.id);
    } on ModelAlreadyLoadingException catch (error) {
      if (mounted) _notice(error.toString());
    } catch (error) {
      // The model row flips to "Could not load model"; keep the reason so
      // the hero can say why. The inference provider has already logged it
      // and may hold a friendlier message (the memory hint for big models).
      if (mounted) {
        final shown = ref.read(inferenceNotifierProvider).error ?? error;
        setState(() => _loadFailure = (
              modelId: model.id,
              reason: shown is StateError ? shown.message : '$shown',
            ));
      }
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
      if (_loadFailure?.modelId == model.id) _loadFailure = null;
      _downloadRequests.add(model.id);
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
        models.where((m) => m.id == kStarterModelId).firstOrNull ??
        models.firstOrNull;

    _ModelPresentation presentation(Model model) {
      // The engine, not the saved row, says which model is loaded.
      final status = ready?.id == model.id
          ? ModelStatus.loaded
          : model.status == ModelStatus.loaded
              ? ModelStatus.downloaded
              : model.status;
      return _ModelPresentation(
        model: model,
        status: status,
        live: service.isDownloading(model.id),
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
    final heroAction = item == null
        ? null
        : heroLoaded
            ? (loading || _unloading ? null : () => _startChat(item.model))
            : actionFor(item);
    final failure = item != null &&
            item.status == ModelStatus.error &&
            _loadFailure?.modelId == item.model.id
        ? _loadFailure!.reason
        : null;
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
              minimumSize: const Size.square(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
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
                variant: PrismHeroVariant.violet,
                artImageAsset: kChipArt,
                status: _focusedId == null &&
                        item.model.id == kStarterModelId &&
                        item.status == ModelStatus.available
                    ? 'Suggested starter'
                    : item.label,
                statusGlyph: item.statusGlyph,
                announceStatus: !item.live,
                title: item.model.name,
                detail: Text(
                  heroLoaded
                      ? 'You can now chat offline.'
                      : failure ?? item.metadata,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                progress: item.live || item.status == ModelStatus.loading
                    ? PrismHeroProgress(
                        key: ValueKey(item.model.id),
                        value: item.fraction,
                        semanticsLabel: item.live ? 'Download progress' : null,
                        glide: kDownloadProgressInterval,
                      )
                    : null,
                actionLabel: item.actionLabel,
                actionGlyph: item.actionIcon,
                cornerActionLabel: heroLoaded ? 'Unload' : null,
                cornerActionGlyph: PrismGlyph.unload,
                onCornerAction: heroLoaded && !_unloading
                    ? () => _unload(item.model)
                    : null,
                onAction: heroAction,
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const PrismSectionHeader('Model library',
                    padding: EdgeInsets.fromLTRB(6, 6, 6, 0), divider: false),
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
              PrismErrorBanner(
                message: 'Could not load the model library',
                retryTooltip: 'Reload model library',
                onRetry: () => ref.invalidate(modelsNotifierProvider),
              )
            else if (models.isEmpty)
              PrismEmptyState(
                glyph: PrismGlyph.relay,
                title: 'No models yet',
                message: 'Import a model file from this phone to get started.',
                actionLabel: _choosingFile ? 'Opening…' : 'Import model',
                onAction: loading || _choosingFile ? null : _sideload,
              )
            else
              Column(
                children: [
                  // The header's line, hidden like the others when the
                  // first row is selected.
                  Divider(
                    height: 1,
                    color: models.first.id == selected?.id
                        ? PrismRelay.lineStrong.withValues(alpha: 0)
                        : PrismRelay.lineStrong,
                  ),
                  for (final (index, row) in models.map(presentation).indexed) ...[
                    _ModelRow(
                      key: ValueKey('model-${row.model.id}'),
                      index: index,
                      item: row,
                      selected: row.model.id == selected?.id,
                      onSelect: loading
                          ? null
                          : () {
                              Haptics.selection();
                              setState(() => _focusedId = row.model.id);
                            },
                      onAction: actionFor(row),
                    ),
                    if (index != models.length - 1)
                      // No line touching the selected row: it would poke
                      // out past the rounded border's corners.
                      Divider(
                        height: 1,
                        color: row.model.id == selected?.id ||
                                models[index + 1].id == selected?.id
                            ? PrismRelay.line.withValues(alpha: 0)
                            : PrismRelay.line,
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
          color: PrismRelay.canvas,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ExcludeSemantics(
                  child: Image.asset(kChipArt, width: 220, height: 220),
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
                // Loading reports no progress, so the bar can only sweep;
                // reduced motion drops it and the copy carries the state.
                if (!MediaQuery.disableAnimationsOf(context)) ...[
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                ],
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
        ModelStatus.loaded => 'Start a chat',
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
        ModelStatus.loaded => PrismGlyph.send,
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
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = item.model;
    final (tileBg, tileInk) = PrismRelay.identityTile(index);
    // The hero and the row's action button carry the state. The only state
    // line a row keeps is a live transfer, over the badge, so a download
    // stays visible on every row.
    final showDownloading =
        item.status == ModelStatus.downloading && item.live;
    final badge = item.model.recommendationBadge;
    return Semantics(
      selected: selected,
      button: true,
      label: model.name,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(16),
          splashColor: PrismRelay.lilacSoft.withValues(alpha: .6),
          highlightColor: PrismRelay.lilacSoft.withValues(alpha: .3),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : PrismRelay.motion,
            curve: PrismRelay.curve,
            decoration: BoxDecoration(
              // Fade to a clear lilac, not Colors.transparent: that is
              // transparent black, and the lerp would flash grey.
              color: selected
                  ? PrismRelay.lilacSoft
                  : PrismRelay.lilacSoft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? PrismRelay.periwinkle
                    : PrismRelay.periwinkle.withValues(alpha: 0),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 11, 6, 11),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 42,
                    child: PrismIcon(
                      PrismGlyph.models,
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
                        maxLines: 2,
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
                      if (showDownloading)
                        // Plain text with fixed-width digits: the numbers
                        // tick in place instead of cross-fading each update.
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: PrismRelay.plum,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: PrismRelay.numbers,
                            ),
                          ),
                        )
                      else if (badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _GrayPill(badge),
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
                    // White on the selected row, so the button stays a tile
                    // on the row's own lilac.
                    backgroundColor:
                        selected ? PrismRelay.surface : PrismRelay.lilacSoft,
                    foregroundColor: PrismRelay.plum,
                    minimumSize: const Size.square(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ],
            ),
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

/// Quiet recommendation pill — same warm grey for every badge so only the
/// icon tiles carry color.
class _GrayPill extends StatelessWidget {
  const _GrayPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PrismRelay.pillGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PrismRelay.pillGrayInk,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
