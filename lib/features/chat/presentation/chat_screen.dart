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

String _sectionFor(int updatedAtMs, DateTime now) {
  final then = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final todayDate = DateTime(now.year, now.month, now.day);
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
            progress: pending
                ? const SizedBox(width: 150, child: PrismHeroProgress())
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
      appBar: AppBar(title: const Text('Chat')),
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
                return ListView(children: [
                  PrismEmptyState(
                    glyph: PrismGlyph.chat,
                    title: 'No chats yet',
                    message:
                        'Everything stays on this device — your chats never leave it.',
                    actionLabel: 'New chat',
                    onAction: startNewConversation,
                  ),
                ]);
              }
              // The repository returns newest first.
              final now = DateTime.now();
              final sections = [
                for (final conv in conversations)
                  _sectionFor(conv.updatedAtMs, now),
              ];
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  final storedId = conv.modelId;
                  final modelName =
                      storedId.isEmpty ? '' : (modelNames[storedId] ?? storedId);
                  final section = sections[index];
                  final showsHeader =
                      index == 0 || sections[index - 1] != section;
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
                          now: now,
                        ),
                        showDivider: index != conversations.length - 1 &&
                            sections[index + 1] == section,
                        onTap: () {
                          Haptics.selection();
                          context.go('/chat/${conv.id}');
                        },
                        onDelete: () async {
                          final confirmed = await confirmDestructive(
                            context,
                            title: 'Delete conversation?',
                            message: conv.title,
                            confirmLabel: 'Delete',
                          );
                          if (confirmed && context.mounted) {
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
