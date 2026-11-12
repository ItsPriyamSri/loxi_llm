import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_blocks.dart';
import '../../../core/widgets/prism_hero.dart';
import '../../../core/widgets/prism_icon.dart';
import '../../models/presentation/models_notifier.dart';
import 'conversation_list_notifier.dart';
import 'widgets/chat_markdown_text.dart';

/// Subtitle for a chat row. Empty [modelName] is just the time, so a chat
/// with no saved model does not say "No model".
String conversationMeta({
  required String modelName,
  required int updatedAtMs,
  DateTime? now,
}) {
  final when = _timeAgo(updatedAtMs, now ?? DateTime.now());
  if (modelName.isEmpty) return when;
  return '$modelName · $when';
}

String _timeAgo(int updatedAtMs, DateTime now) {
  final then = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final delta = now.difference(then);
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${then.day} ${months[then.month - 1]}';
}

String _sectionFor(int updatedAtMs, [DateTime? now]) {
  final then = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final today = now ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final thenDate = DateTime(then.year, then.month, then.day);
  final days = todayDate.difference(thenDate).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  if (days < 30) return 'This month';
  return 'Earlier';
}

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(inferenceNotifierProvider);

    if (backendAsync.asData?.value != null) {
      return const _ConversationListView();
    }
    final pending = backendAsync.isLoading;
    final failed = backendAsync.hasError;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          PrismHero(
            variant: PrismHeroVariant.violet,
            artImageAsset: kChipArt,
            status: pending ? 'Loading' : failed ? 'Could not load' : 'No model',
            statusGlyph: pending
                ? PrismGlyph.relay
                : failed
                    ? PrismGlyph.warn
                    : PrismGlyph.lock,
            title: pending
                ? 'Warming up…'
                : failed
                    ? 'Could not load model'
                    : 'Load a model to chat',
            detail: pending
                ? const Text('This happens once per model.')
                : failed
                    ? const Text('Open Models and try loading it again.')
                    : const Text('Your first reply works offline.'),
            progress: pending && !MediaQuery.disableAnimationsOf(context)
                ? const SizedBox(
                    width: 150,
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                      color: PrismRelay.peach,
                      backgroundColor: Color(0x3DFFFFFF),
                    ),
                  )
                : null,
            actionLabel: pending ? null : 'Open Models',
            actionGlyph: PrismGlyph.models,
            onAction: pending ? null : () => context.go('/models'),
          ),
        ],
      ),
    );
  }
}

class _ConversationListView extends ConsumerWidget {
  const _ConversationListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationListNotifierProvider);
    final notifier = ref.read(conversationListNotifierProvider.notifier);
    ref.watch(inferenceNotifierProvider);
    final loadedModel =
        ref.read(inferenceNotifierProvider.notifier).loadedModel;
    final modelNames = {
      for (final model
          in ref.watch(modelsNotifierProvider).valueOrNull ?? const [])
        model.id: model.name,
    };

    void startNewConversation() {
      Haptics.commit();
      final id = notifier.createConversation(modelId: loadedModel?.id ?? '');
      context.go('/chat/$id');
    }

    final isEmpty = conversationsAsync.valueOrNull?.isEmpty ?? false;
    return Scaffold(
      backgroundColor: PrismRelay.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('Chat'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: PrismAmbientWash()),
          conversationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(conversationListNotifierProvider),
                child: const Text('Could not load chats. Try again'),
              ),
            ),
            data: (conversations) {
              if (conversations.isEmpty) {
                return _EmptyChats(onStart: startNewConversation);
              }
              final sorted = [...conversations]
                ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final conv = sorted[index];
                  final storedId = conv.modelId;
                  final modelName =
                      storedId.isEmpty ? '' : (modelNames[storedId] ?? storedId);
                  final section = _sectionFor(conv.updatedAtMs);
                  final showsHeader =
                      index == 0 || _sectionFor(sorted[index - 1].updatedAtMs) != section;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showsHeader) PrismSectionHeader(section),
                      _ConversationRow(
                        key: ValueKey('chat-${conv.id}'),
                        index: index,
                        title: conv.title,
                        subtitle: conversationMeta(
                          modelName: modelName,
                          updatedAtMs: conv.updatedAtMs,
                        ),
                        showDivider: index != sorted.length - 1 &&
                            _sectionFor(sorted[index + 1].updatedAtMs) == section,
                        onTap: () {
                          Haptics.selection();
                          context.go('/chat/${conv.id}');
                        },
                        onDelete: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete conversation?'),
                              content: Text(conv.title),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            Haptics.tap();
                            notifier.deleteConversation(conv.id);
                          }
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      floatingActionButton: isEmpty
          ? null
          : _NewChatFab(onPressed: startNewConversation),
    );
  }
}

/// Extended "New chat" action button — gradient pill, brand shadow,
/// always reachable above the dock.
class _NewChatFab extends StatelessWidget {
  const _NewChatFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const ValueKey('new-chat-fab'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: PrismRelay.accentGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: PrismRelay.shadowRaised,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 56),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrismIcon(PrismGlyph.plus, size: 20, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'New chat',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: Colors.white,
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

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: 44),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: PrismRelay.lilacSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const SizedBox.square(
                    dimension: 72,
                    child: PrismIcon(PrismGlyph.chat,
                        size: 30, color: PrismRelay.plum),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text('No chats yet', style: type.headlineSmall),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Everything stays on this device — your chats never leave it.',
                  textAlign: TextAlign.center,
                  style: type.bodyMedium?.copyWith(color: PrismRelay.inkMuted),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton.icon(
                  icon: const PrismIcon(PrismGlyph.plus, size: 18),
                  label: const Text('New chat'),
                  onPressed: onStart,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
    this.showDivider = true,
  });

  final int index;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final (tileBg, tileInk) = PrismRelay.identityTile(index);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 11, 2, 11),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: PrismIcon(
                      PrismGlyph.chat,
                      size: 20,
                      color: tileInk,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChatMarkdownText(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        inlineOnly: true,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: PrismRelay.inkMuted,
                              fontSize: 12.5,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const PrismIcon(PrismGlyph.trash,
                      size: 19, color: PrismRelay.inkSecondary),
                  tooltip: 'Delete chat',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            color: PrismRelay.line,
          ),
      ],
    );
  }
}
