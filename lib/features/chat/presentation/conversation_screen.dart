import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/engine/inference_backend.dart';
import '../../../core/providers/download_provider.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/file_storage_service.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_icon.dart';
import '../../agent/agent_model_support.dart';
import '../../models/domain/model.dart';
import '../../settings/presentation/prompt_library_screen.dart';
import '../../settings/presentation/settings_notifier.dart';
import '../application/conversation_markdown_exporter.dart';
import '../data/conversation_repository.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import '../domain/message_role.dart';
import 'chat_notifier.dart';
import 'conversation_list_notifier.dart';
import 'widgets/chat_markdown_text.dart';
import 'widgets/image_attachment_thumbnail.dart';
import 'widgets/message_bubble.dart';

/// Whether a pending image attachment should survive an inference-state
/// change. True while a load is in flight ([next] is [AsyncLoading]) — only
/// a settled `AsyncData`/`AsyncError` should ever decide to drop an
/// attachment, otherwise reloading (or switching between) vision-capable
/// models would wipe it on every transient loading tick. Once settled, true
/// only when [loadedModel] is both catalog-multimodal and the new backend
/// itself reports vision support.
bool stillAllowsAttachment(
  AsyncValue<InferenceBackend?> next,
  Model? loadedModel,
) {
  if (next is AsyncLoading) return true;
  return loadedModel != null &&
      isMultimodalModel(loadedModel) &&
      (next.valueOrNull?.supportsVision ?? false);
}

/// Path to put back into the composer after [ChatNotifier.send] throws, or
/// null to leave the attachment cleared.
///
/// `send()` throws before persisting in two cases today: no model loaded
/// (file still on disk — restore so the user can retry) and attached image
/// missing (file gone — leave cleared; restoring would show a broken
/// thumbnail while the SnackBar already asked them to re-attach).
Future<String?> attachedPathToRestoreAfterSendError(String? imagePath) async {
  if (imagePath == null) return null;
  if (!await File(imagePath).exists()) return null;
  return imagePath;
}

/// Whether `_sendMessage`'s composer should restore its cleared text and
/// attachment after `send()` throws [error] — true for a pre-persist
/// failure (nothing was actually sent, so there's something worth
/// retrying), false for [SendFailedAfterPersistException] (the message
/// already went through; restoring would risk a near-duplicate resend).
bool shouldRestoreComposerAfterSendError(Object error) =>
    error is! SendFailedAfterPersistException;

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;

  /// Message id currently being read aloud, if any.
  String? _speakingMessageId;

  /// True after pause, until resume, stop, or a different message.
  bool _readAloudPaused = false;

  /// Read in initState. [dispose] cannot use `ref`.
  late final TtsService _tts;
  late final FileStorageService _storage;
  bool _following = true;
  bool _newerBelow = false;
  bool _submitting = false;
  bool _stopRequested = false;
  bool _pickingImage = false;
  String? _sendError;

  /// Path to an image attached to the message being composed, if any. Copied
  /// into app storage so it survives independently of the picker's temp file.
  String? _attachedImagePath;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _scrollController = ScrollController();
    _tts = ref.read(ttsServiceProvider);
    _storage = ref.read(fileStorageServiceProvider);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _tts.stop();
    _textController.dispose();
    _scrollController.dispose();
    if (_attachedImagePath != null) {
      // Fire-and-forget: dispose() can't be async. An unsent attachment
      // shouldn't outlive the screen it was picked on.
      _storage.deleteImage(_attachedImagePath!);
    }
    super.dispose(); // MUST be last
  }

  bool _onScroll(ScrollNotification event) {
    if (event.depth != 0) return false;
    final isUserScroll = event is UserScrollNotification ||
        (event is ScrollUpdateNotification && event.dragDetails != null);
    if (isUserScroll) {
      final atLatest = event.metrics.extentAfter <= 56;
      if (_following != atLatest || (atLatest && _newerBelow)) {
        setState(() {
          _following = atLatest;
          if (atLatest) _newerBelow = false;
        });
      }
    }
    return false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.extentAfter <= 1) return;
      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  Future<void> _sendMessage() async {
    Haptics.commit();
    if (_submitting ||
        ref.read(inferenceNotifierProvider).asData?.value == null) {
      return;
    }
    final rawText = _textController.text;
    final text = rawText.trim();
    final imagePath = _attachedImagePath;
    if (text.isEmpty && imagePath == null) return;
    // Clear the composer immediately/optimistically, text and attachment
    // together, rather than waiting for send() to resolve — which for an
    // agent-mode turn can take a long time (it awaits the whole turn, not
    // just the initial call). Hand off ownership of the attachment to
    // send() at the same time: once it persists the message, the message
    // (not the composer) owns the file, so dispose()/the vision-gate below
    // must no longer touch it — otherwise a slow send() (RAG retrieval,
    // summarization) leaves a window where navigating away or switching
    // models deletes a file the already-persisted message still points to.
    //
    // On a pre-persist throw (nothing sent), both are restored together —
    // the attachment only if the file still exists, see
    // [attachedPathToRestoreAfterSendError]. On a post-persist one
    // ([SendFailedAfterPersistException]), neither is restored: the message
    // already went through, so putting the text/attachment back would risk
    // a near-duplicate resend. See [shouldRestoreComposerAfterSendError].
    _textController.clear();
    setState(() {
      _attachedImagePath = null;
      _submitting = true;
      _following = true;
      _newerBelow = false;
      _sendError = null;
    });
    try {
      await ref
          .read(chatNotifierProvider(widget.conversationId).notifier)
          .send(text, imagePath: imagePath);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final shouldRestore = shouldRestoreComposerAfterSendError(e);
      if (shouldRestore) {
        _textController.text = rawText;
        final restore = await attachedPathToRestoreAfterSendError(imagePath);
        if (!mounted) return;
        if (restore != null) setState(() => _attachedImagePath = restore);
      } else {
        // The message was already persisted and is showing in the chat
        // above — nothing to retry, just scroll to it.
        _scrollToBottom();
      }
      setState(() {
        _sendError = shouldRestore
            ? 'Could not send the message. Your draft is still here.'
            : 'Message saved, but the reply could not start.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final picked = result?.files.single;
      if (picked?.path == null || !mounted) return;

      final storage = _storage;
      final filename =
          'img-${DateTime.now().millisecondsSinceEpoch}${_extensionOf(picked!)}';
      final destPath = await storage.getImagePath(filename);
      await File(picked.path!).copy(destPath);

      // Replace any previously attached (unsent) image so it doesn't leak.
      final previous = _attachedImagePath;
      if (!mounted) {
        await storage.deleteImage(destPath);
        return;
      }
      if (!stillAllowsAttachment(
        ref.read(inferenceNotifierProvider),
        ref.read(inferenceNotifierProvider.notifier).loadedModel,
      )) {
        await storage.deleteImage(destPath);
        _showSnack('The selected model does not support images.');
        return;
      }
      setState(() => _attachedImagePath = destPath);
      if (previous != null) await storage.deleteImage(previous);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not attach image.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// [PlatformFile.extension] splits the picked *filename*, not the full
  /// path — unlike splitting the path directly, it isn't fooled by dots
  /// earlier in an Android cache path (e.g. a package name). Falls back to
  /// `.jpg` when the filename itself has no extension (e.g. some picker
  /// implementations return an extensionless scaled-cache filename).
  String _extensionOf(PlatformFile file) {
    final ext = file.extension;
    if (ext == null || ext == file.name) return '.jpg';
    return '.$ext';
  }

  void _removeAttachedImage() {
    final stale = _attachedImagePath;
    setState(() => _attachedImagePath = null);
    if (stale != null) _storage.deleteImage(stale);
  }

  Future<void> _openAddSheet({
    required bool agentCapable,
    required bool canAttachImage,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _AttachSheet(
        conversationId: widget.conversationId,
        agentCapable: agentCapable,
        canAttachImage: canAttachImage,
        pickingImage: _pickingImage,
        onPickImage: () {
          Navigator.of(sheetContext).pop();
          Haptics.selection();
          _pickImage();
        },
      ),
    );
  }

  Future<void> _editSystemPrompt() async {
    final conversation =
        ref.read(conversationRepositoryProvider).getById(widget.conversationId);
    if (conversation == null) return;

    final controller = TextEditingController(text: conversation.systemPrompt);
    final route = DialogRoute<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final prompts =
              ref.read(settingsNotifierProvider.notifier).savedPrompts();
          return AlertDialog(
            title: const Text('System Prompt'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'System prompt',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (prompts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final prompt in prompts)
                            ActionChip(
                              label: Text(prompt.name),
                              onPressed: () {
                                controller.text = prompt.body;
                                controller.selection = TextSelection.collapsed(
                                  offset: controller.text.length,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  await _savePromptToLibrary(controller.text);
                  if (ctx.mounted) setDialogState(() {});
                },
                child: const Text('Save to library'),
              ),
              TextButton(
                onPressed: () {
                  ref
                      .read(conversationListNotifierProvider.notifier)
                      .updateSystemPrompt(
                        widget.conversationId,
                        controller.text,
                      );
                  Navigator.of(ctx).pop();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    controller.dispose();
  }

  Future<void> _savePromptToLibrary(String body) async {
    final taken = ref.read(settingsNotifierProvider.notifier).savedPrompts();
    final name = await askPromptName(
      context,
      nameTaken: (candidate) => taken.any((prompt) => prompt.name == candidate),
    );
    if (!mounted || name == null) return;
    ref.read(settingsNotifierProvider.notifier).savePrompt(name, body);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _copyText(String text, {required String confirmation}) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack(confirmation);
  }

  Future<void> _shareConversation(
    Conversation conversation,
    List<Message> messages,
  ) async {
    if (messages.isEmpty) {
      _showSnack('Nothing to export yet');
      return;
    }
    final markdown = exportConversationMarkdown(
      conversation: conversation,
      messages: messages,
    );
    await SharePlus.instance.share(
      ShareParams(text: markdown, subject: conversation.title),
    );
  }

  Future<void> _copyConversation(
    Conversation conversation,
    List<Message> messages,
  ) async {
    if (messages.isEmpty) {
      _showSnack('Nothing to copy yet');
      return;
    }
    await _copyText(
      exportConversationMarkdown(
        conversation: conversation,
        messages: messages,
      ),
      confirmation: 'Conversation copied to clipboard',
    );
  }

  Future<void> _stopReadAloud() async {
    setState(() {
      _speakingMessageId = null;
      _readAloudPaused = false;
    });
    await _tts.stop();
  }

  Future<void> _stopGeneration() async {
    Haptics.tap();
    if (_stopRequested) return;
    setState(() => _stopRequested = true);
    try {
      await Future.wait([
        ref.read(chatNotifierProvider(widget.conversationId).notifier).stop(),
        if (_speakingMessageId != null) _stopReadAloud(),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stopRequested = false);
      _showSnack('Could not stop generation.');
    }
  }

  Future<void> _toggleReadAloud(Message message) async {
    final tts = _tts;
    if (!tts.isSupported) {
      _showSnack('Read aloud is available on Android');
      return;
    }
    final rate = ref.read(settingsNotifierProvider).speechRate;
    final same = _speakingMessageId == message.id;
    if (same && !_readAloudPaused) {
      // Set this before pause returns. Pause completes the in-flight speak,
      // and that completion must not clear the button.
      setState(() => _readAloudPaused = true);
      final paused = await tts.pause();
      if (!mounted) return;
      if (!paused) {
        setState(() {
          _speakingMessageId = null;
          _readAloudPaused = false;
        });
      }
      return;
    }
    if (same && _readAloudPaused) {
      setState(() => _readAloudPaused = false);
      await tts.resume(rate: rate);
      if (mounted && _speakingMessageId == message.id && !_readAloudPaused) {
        setState(() => _speakingMessageId = null);
      }
      return;
    }
    setState(() {
      _speakingMessageId = message.id;
      _readAloudPaused = false;
    });
    await tts.speak(message.content, rate: rate);
    if (mounted && _speakingMessageId == message.id && !_readAloudPaused) {
      setState(() => _speakingMessageId = null);
    }
  }

  Widget _shortcuts({required bool centered}) {
    const shortcuts = [
      ('Explain', 'Explain the following in simple terms:\n'),
      ('Summarize', 'Summarize the following in 3 bullet points:\n'),
      ('Refine', 'Refine and improve the following text:\n'),
      ('Translate', 'Translate the following to English:\n'),
    ];
    final actions = [
      for (final (label, prompt) in shortcuts)
        _ShortcutChip(
          label: label,
          onPressed: () {
            Haptics.selection();
            _textController.value = TextEditingValue(
              text: prompt,
              selection: TextSelection.collapsed(offset: prompt.length),
            );
          },
        ),
    ];
    if (centered) {
      return Wrap(
        key: const ValueKey('centered-shortcuts'),
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: actions,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('quick-shortcuts'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(spacing: 6, children: actions),
    );
  }

  void _openModels() {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      shell.goBranch(0);
    } else {
      GoRouter.maybeOf(context)?.go('/models');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = chatNotifierProvider(widget.conversationId);
    final chatAsync = ref.watch(chatProvider);
    final backendAsync = ref.watch(inferenceNotifierProvider);
    final repository = ref.watch(conversationRepositoryProvider);
    final conversations = ref.watch(conversationListNotifierProvider);
    final conversation = conversations.valueOrNull
            ?.where((item) => item.id == widget.conversationId)
            .firstOrNull ??
        repository.getById(widget.conversationId);
    final canNavigate = GoRouter.maybeOf(context) != null;
    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This conversation is no longer available.'),
              if (canNavigate)
                TextButton(
                    onPressed: () => context.go('/chat'),
                    child: const Text('Back to chats')),
            ],
          ),
        ),
      );
    }

    final loadedModel =
        ref.read(inferenceNotifierProvider.notifier).loadedModel;
    final backend = backendAsync.asData?.value;
    final ready = backend != null;
    final agentCapable = ready && isAgentCapableModel(loadedModel?.id);
    final canAttachImage = loadedModel != null &&
        isMultimodalModel(loadedModel) &&
        (backend?.supportsVision ?? false);
    final chat = chatAsync.valueOrNull;
    final messages = chat?.messages ?? const <Message>[];
    final streamingText = chat?.streamingText;
    final isStreaming = chat?.isStreaming ?? false;
    final blank = chat != null && messages.isEmpty && !isStreaming;
    ref.watch(settingsNotifierProvider);
    final savedPrompts =
        ref.read(settingsNotifierProvider.notifier).savedPrompts();
    final prompts = savedPrompts.take(6).toList();
    final modeActions = ref.read(conversationListNotifierProvider.notifier);
    final theme = Theme.of(context);

    ref.listen(inferenceNotifierProvider, (previous, next) {
      final model = ref.read(inferenceNotifierProvider.notifier).loadedModel;
      if (!stillAllowsAttachment(next, model) && _attachedImagePath != null) {
        _removeAttachedImage();
        _showSnack('Image removed. The selected model does not support it.');
      }
    });
    ref.listen(chatProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (after == null ||
          (before?.messages.length == after.messages.length &&
              before?.streamingText == after.streamingText)) {
        return;
      }
      if (_stopRequested && before?.isStreaming == true && !after.isStreaming) {
        setState(() => _stopRequested = false);
        if (after.error == null) _showSnack('Generation stopped');
      }
      if (_following) {
        _scrollToBottom();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _following || !_scrollController.hasClients) return;
          final below = _scrollController.position.extentAfter > 56;
          if (_newerBelow != below) setState(() => _newerBelow = below);
        });
      }
    });

    final error = _sendError ?? chat?.error;
    final showJump = !_following && _newerBelow;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight:
            MediaQuery.textScalerOf(context).scale(16) > 23 ? 80 : 60,
        leading: Navigator.canPop(context) ? const BackButton() : null,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatMarkdownText(
              conversation.title,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              inlineOnly: true,
            ),
            if (ready && loadedModel != null)
              Row(
                children: [
                  const PrismIcon(PrismGlyph.lock,
                      size: 11, color: PrismRelay.violetDeep),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${loadedModel.name} · On device',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: PrismRelay.violetDeep,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'System prompt',
                icon: const PrismIcon(PrismGlyph.book),
                onPressed: _editSystemPrompt,
              ),
              if (conversation.systemPrompt.isNotEmpty)
                const Positioned(
                  top: 9,
                  right: 9,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: PrismRelay.accent,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 8),
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const PrismIcon(PrismGlyph.more),
            tooltip: 'Export conversation',
            onSelected: (value) {
              if (value == 'share') {
                _shareConversation(conversation, messages);
              } else {
                _copyConversation(conversation, messages);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: Text('Share as Markdown')),
              PopupMenuItem(value: 'copy', child: Text('Copy conversation')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-.95, -.85),
                  radius: 1.2,
                  colors: [Color(0x66E9DFF7), Color(0x00E9DFF7)],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.05, .9),
                  radius: 1.25,
                  colors: [Color(0x55FDEBDD), Color(0x00FDEBDD)],
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, viewport) => Column(
            children: [
              if (!ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Card(
                    color: backendAsync.hasError
                        ? PrismRelay.blush
                        : PrismRelay.peachSurface,
                    child: ListTile(
                      title: Text(backendAsync.isLoading
                          ? 'Loading model…'
                          : backendAsync.hasError
                              ? 'Could not load model'
                              : 'No model loaded'),
                      trailing: canNavigate && !backendAsync.isLoading
                          ? TextButton(
                              onPressed: _openModels,
                              child: const Text('Models'))
                          : null,
                    ),
                  ),
                ),
              Expanded(
                child: chatAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: TextButton(
                      onPressed: () => ref.invalidate(chatProvider),
                      child: const Text('Could not open messages. Try again'),
                    ),
                  ),
                  data: (chatState) {
                    if (blank) {
                      final showTemplates = conversation.systemPrompt.isEmpty &&
                          prompts.isNotEmpty;
                      return Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : PrismRelay.motion,
                            switchInCurve: PrismRelay.curve,
                            switchOutCurve: PrismRelay.curve,
                            child: showTemplates
                                ? Column(
                                    key: const ValueKey('saved-prompts'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const PrismBrandMark(size: 46),
                                      const SizedBox(height: 16),
                                      Text(
                                        "What's on your mind?",
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.displaySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Pick a template, or ask Loki anything.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: PrismRelay.inkSecondary),
                                      ),
                                      const SizedBox(height: 18),
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          childAspectRatio: 3.1,
                                        ),
                                        itemCount: prompts.length,
                                        itemBuilder: (context, index) =>
                                            _TemplateChip(
                                          name: prompts[index].name,
                                          onTap: () {
                                            Haptics.selection();
                                            modeActions.updateSystemPrompt(
                                                widget.conversationId,
                                                prompts[index].body);
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton.icon(
                                        key: const ValueKey('more-templates'),
                                        onPressed: () => context.push('/prompts'),
                                        iconAlignment: IconAlignment.end,
                                        icon: const PrismIcon(PrismGlyph.chevron,
                                            size: 18),
                                        label: const Text('More templates'),
                                      ),
                                    ],
                                  )
                                : Column(
                                    key: const ValueKey('center-shortcuts'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const PrismBrandMark(size: 46),
                                      const SizedBox(height: 16),
                                      Text(
                                        "What's on your mind?",
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.displaySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Short on words? Start with one of these.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: PrismRelay.inkSecondary),
                                      ),
                                      const SizedBox(height: 18),
                                      _shortcuts(centered: true),
                                    ],
                                  ),
                          ),
                        ),
                      );
                    }
                    return NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount:
                            messages.length + (streamingText == null ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            final text = streamingText!;
                            return MessageBubble(
                              content: text,
                              isUser: false,
                              isStreaming: true,
                              child: text.isEmpty
                                  ? const _ThinkingRow()
                                  : null,
                            );
                          }
                          final message = messages[index];
                          final hasText = message.content.trim().isNotEmpty;
                          final stats = replyStats(
                            tokenCount: message.tokenCount,
                            totalDurationMs: message.totalDurationMs,
                            timeToFirstTokenMs: message.timeToFirstTokenMs,
                            replyWaitMs: message.replyWaitMs,
                          );
                          return MessageBubble(
                            content: message.content,
                            imagePath: message.imagePath,
                            isUser: message.role == MessageRole.user,
                            isStreaming: false,
                            onCopy: hasText
                                ? () => _copyText(message.content,
                                    confirmation: 'Message copied')
                                : null,
                            onReadAloud:
                                hasText && message.role == MessageRole.assistant
                                    ? () => _toggleReadAloud(message)
                                    : null,
                            onStopReadAloud: _speakingMessageId == message.id
                                ? _stopReadAloud
                                : null,
                            isSpeaking: _speakingMessageId == message.id &&
                                !_readAloudPaused,
                            isPaused: _speakingMessageId == message.id &&
                                _readAloudPaused,
                            speedLabel: stats?.speed,
                            timeLabel: stats?.time,
                            child: !hasText &&
                                    message.role == MessageRole.assistant
                                ? const Text('No reply generated')
                                : null,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : PrismRelay.motion,
                child: showJump
                    ? Align(
                        key: const ValueKey('jump-pill'),
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _JumpPill(
                            onTap: () {
                              Haptics.selection();
                              setState(() {
                                _following = true;
                                _newerBelow = false;
                              });
                              _scrollToBottom();
                            },
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('jump-pill-hidden')),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: PrismRelay.blush,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: const Color(0xFFF3C4C4)),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          const PrismIcon(PrismGlyph.warn,
                              size: 20, color: PrismRelay.errorInk),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: PrismRelay.errorInk,
                                        fontSize: 13,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (blank &&
                  conversation.systemPrompt.isEmpty &&
                  prompts.isNotEmpty &&
                  !isStreaming &&
                  MediaQuery.viewInsetsOf(context).bottom == 0)
                _shortcuts(centered: false),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: PrismRelay.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: PrismRelay.lineStrong),
                    boxShadow: PrismRelay.shadowRaised,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_attachedImagePath != null)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(start: 12),
                            child: Row(
                              children: [
                                ImageAttachmentThumbnail(
                                    path: _attachedImagePath!,
                                    size: 64,
                                    borderRadius: 8),
                                IconButton(
                                  icon: const PrismIcon(PrismGlyph.close),
                                  tooltip: 'Remove image',
                                  onPressed: _removeAttachedImage,
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('add-to-message'),
                              icon: const PrismIcon(PrismGlyph.plus,
                                  color: PrismRelay.inkSecondary),
                              tooltip: 'Add to message',
                              onPressed: () {
                                Haptics.selection();
                                _openAddSheet(
                                  agentCapable: agentCapable,
                                  canAttachImage: canAttachImage,
                                );
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                decoration: const InputDecoration(
                                  hintText: 'Message Loki',
                                  hintMaxLines: 1,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 8),
                                ),
                                minLines: 1,
                                maxLines: viewport.maxHeight < 380 ? 2 : 3,
                                onSubmitted:
                                    ready && !isStreaming && !_submitting
                                        ? (_) => _sendMessage()
                                        : null,
                              ),
                            ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _textController,
                              builder: (_, value, __) => IconButton.filled(
                                key: const ValueKey('send-stop'),
                                tooltip: isStreaming
                                    ? _stopRequested
                                        ? 'Stopping generation'
                                        : 'Stop generating'
                                    : 'Send message',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size.square(46),
                                  backgroundColor: isStreaming
                                      ? PrismRelay.violetDeep
                                      : PrismRelay.accent,
                                  foregroundColor: PrismRelay.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                ),
                                icon: PrismIcon(isStreaming
                                    ? PrismGlyph.stop
                                    : PrismGlyph.send),
                                onPressed: isStreaming
                                    ? _stopRequested
                                        ? null
                                        : _stopGeneration
                                    : ready &&
                                            !_submitting &&
                                            (value.text.trim().isNotEmpty ||
                                                _attachedImagePath != null)
                                        ? _sendMessage
                                        : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }
}

/// Compact shortcut chip shown above the composer (and centered in the
/// blank state once a template is chosen). Quiet fill, ink text, one
/// saturated tint per chip is not used — the action is the color.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PrismIcon(PrismGlyph.spark,
                    size: 13, color: PrismRelay.plum),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: PrismRelay.violetDeep,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
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

/// One cell of the 2 x 3 starter-template grid on the blank new-chat page.
class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrismRelay.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PrismRelay.lineStrong),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const PrismIcon(PrismGlyph.book,
                      size: 15, color: PrismRelay.plum),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            height: 1.2,
                            color: PrismRelay.ink,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating "Jump to latest" pill shown while the user reads older turns.
class _JumpPill extends StatelessWidget {
  const _JumpPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: PrismRelay.surface,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: PrismRelay.lineStrong),
            boxShadow: PrismRelay.shadowRaised,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismIcon(PrismGlyph.down, size: 15, color: PrismRelay.violetDeep),
              SizedBox(width: 7),
              Text(
                'Jump to latest',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: PrismRelay.violetDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waiting-on-first-token row: three wave dots and a label, never a spinner
/// over text. Reduced motion renders the static label.
class _ThinkingRow extends StatefulWidget {
  const _ThinkingRow();

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow>
    with SingleTickerProviderStateMixin {
  static final _inTest = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context) || _inTest;
    if (still) {
      _clock.stop();
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
    final label = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: PrismRelay.inkSecondary,
          fontWeight: FontWeight.w600,
        );
    final reduce = MediaQuery.disableAnimationsOf(context) || _inTest;
    return Semantics(
      liveRegion: true,
      label: 'Thinking…',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              child: reduce
                  ? const _Dots(phase: 0)
                  : AnimatedBuilder(
                      animation: _clock,
                      builder: (_, __) => _Dots(phase: _clock.value),
                    ),
            ),
            const SizedBox(width: 8),
            Text('Thinking…', style: label),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 3; i++)
          _Dot(wave: Curves.easeInOut.transform((phase + i * .18) % 1.0)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.wave});

  /// 0 resting → 1 crest.
  final double wave;

  @override
  Widget build(BuildContext context) {
    final lift = wave < .5 ? wave * 2 : (1 - wave) * 2;
    return Transform.translate(
      offset: Offset(0, -3 * lift),
      child: Opacity(
        opacity: .35 + .65 * lift,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: PrismRelay.accent,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 6),
        ),
      ),
    );
  }
}

/// The "+" sheet: one place for everything that is not typed text —
/// attaching a photo, per-chat Documents and Tools. Tools the current model
/// cannot call are shown greyed and stay unclickable.
class _AttachSheet extends ConsumerWidget {
  const _AttachSheet({
    required this.conversationId,
    required this.agentCapable,
    required this.canAttachImage,
    required this.pickingImage,
    required this.onPickImage,
  });

  final String conversationId;
  final bool agentCapable;
  final bool canAttachImage;
  final bool pickingImage;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListNotifierProvider);
    final conversation = conversations.valueOrNull
        ?.where((item) => item.id == conversationId)
        .firstOrNull;
    final rag = conversation?.ragEnabled ?? false;
    final tools = conversation?.toolsEnabled ?? false;
    final actions = ref.read(conversationListNotifierProvider.notifier);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text('Add to this message',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            _AttachRow(
              glyph: PrismGlyph.image,
              tile: PrismRelay.lilacSoft,
              tileInk: PrismRelay.plum,
              title: 'Attach an image',
              subtitle: canAttachImage
                  ? 'For the vision model loaded on this phone'
                  : 'Needs a vision-capable model',
              enabled: canAttachImage && !pickingImage,
              onTap: onPickImage,
            ),
            _AttachRow(
              glyph: PrismGlyph.file,
              tile: PrismRelay.mintSurface,
              tileInk: PrismRelay.greenInk,
              title: 'Documents',
              subtitle: 'Answers use your imported documents',
              enabled: true,
              onTap: () {
                Haptics.selection();
                actions.toggleRagEnabled(conversationId);
              },
              trailing: Switch(
                value: rag,
                onChanged: (_) {
                  Haptics.selection();
                  actions.toggleRagEnabled(conversationId);
                },
              ),
            ),
            _AttachRow(
              glyph: PrismGlyph.tools,
              tile: PrismRelay.peachSurface,
              tileInk: PrismRelay.amberInk,
              title: 'Tools',
              subtitle: agentCapable
                  ? 'Loki may call your allowed tools'
                  : 'Needs a model that can call tools',
              enabled: agentCapable,
              onTap: agentCapable
                  ? () {
                      Haptics.selection();
                      actions.toggleToolsEnabled(conversationId);
                    }
                  : null,
              trailing: Switch(
                value: agentCapable && tools,
                onChanged: agentCapable
                    ? (_) {
                        Haptics.selection();
                        actions.toggleToolsEnabled(conversationId);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.glyph,
    required this.tile,
    required this.tileInk,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.trailing,
  });

  final PrismGlyph glyph;
  final Color tile;
  final Color tileInk;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = !enabled;
    return Opacity(
      opacity: dim ? .42 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tile,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: SizedBox.square(
                    dimension: 38,
                    child: PrismIcon(glyph, size: 18, color: tileInk),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  IgnorePointer(child: trailing),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
