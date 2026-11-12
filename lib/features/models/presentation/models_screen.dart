import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        models.where((m) => m.id == kStarterModelId).firstOrNull ??
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
                    ? _TransferProgress(
                        key: ValueKey(item.model.id), value: item.fraction)
                    : null,
                actionLabel: item.actionLabel,
                actionGlyph: item.actionIcon,
                cornerActionLabel: heroLoaded ? 'Unload' : null,
                cornerActionGlyph: PrismGlyph.unload,
                onCornerAction: heroLoaded && !_unloading
                    ? () => _unload(item.model)
                    : null,
                actionEnabled: heroAction != null,
                onAction: heroAction,
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
              PrismErrorBanner(
                message: 'Could not load the model library',
                retryTooltip: 'Reload model library',
                onRetry: () => ref.invalidate(modelsNotifierProvider),
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
                      'Import a model file from this phone to get started.',
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
                      key: ValueKey('model-${models[index].id}'),
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
                      const Divider(height: 1),
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

/// The layered processor art, gently bobbing. flutter_svg draws SVG
/// statically (no CSS animation, no filters), so all motion lives here.
/// Reduced motion holds it still.
class _LoadingArt extends StatefulWidget {
  const _LoadingArt({required this.width});

  final double width;

  @override
  State<_LoadingArt> createState() => _LoadingArtState();
}

class _LoadingArtState extends State<_LoadingArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.stop();
      _clock.value = .5;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      'assets/art/layered_processor.svg',
      width: widget.width,
    );
    if (MediaQuery.disableAnimationsOf(context)) return svg;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, child) {
        final t = _clock.value * 2 * math.pi;
        final wave = math.sin(t);
        return Transform.translate(
          offset: Offset(0, -6 * (0.5 - 0.5 * math.cos(t))),
          child: Transform.scale(
            scale: 1 + .022 * wave.abs(),
            child: child,
          ),
        );
      },
      child: svg,
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
                  child: _LoadingArt(width: 264),
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
    // Live transfer is the only state line the tile keeps; everything else
    // (saved/errored/stopped) is hero-exclusive so the two never disagree.
    // It wins over the badge so a download is visible on every row.
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
                      if (showDownloading)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : PrismRelay.motion,
                            switchInCurve: PrismRelay.curve,
                            switchOutCurve: PrismRelay.curve,
                            child: Text(
                              item.label,
                              key: ValueKey(item.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: PrismRelay.plum,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
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
                    backgroundColor: PrismRelay.lilacSoft,
                    foregroundColor: PrismRelay.plum,
                    minimumSize: const Size.square(44),
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

/// The transfer bar inside the violet hero: translucent white track, peach
/// fill. Indeterminate until the first byte count arrives.
class _TransferProgress extends StatelessWidget {
  const _TransferProgress({super.key, required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget indicator(double? fraction) => LinearProgressIndicator(
          value: fraction,
          semanticsLabel:
              fraction == null ? 'In progress' : 'Download progress',
          minHeight: 5,
          borderRadius: BorderRadius.circular(6),
          color: PrismRelay.peach,
          backgroundColor: const Color(0x3DFFFFFF),
        );
    if (value == null || reduce) return indicator(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 120),
      builder: (_, progress, __) => indicator(progress),
    );
  }
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
