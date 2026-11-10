import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/providers/inference_provider.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_art.dart';
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          PrismHero(
            title: pending
                ? 'Loading model…'
                : failed
                    ? 'Could not load model'
                    : 'Load a model to chat',
            tint: failed ? PrismRelay.blush : PrismRelay.lilacSoft,
            artwork: PrismArtwork.chat,
            progress: pending && !MediaQuery.disableAnimationsOf(context)
                ? const LinearProgressIndicator()
                : null,
            action: pending
                ? null
                : FilledButton(
                    onPressed: () => context.go('/models'),
                    child: const Text('Open Models'),
                  ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (conversationsAsync.valueOrNull?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton.icon(
                icon: const PrismIcon(PrismGlyph.plus),
                label: const Text('New Chat'),
                onPressed: startNewConversation,
              ),
            ),
        ],
      ),
      body: conversationsAsync.when(
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
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
                  if (showsHeader) _SectionHeader(section),
                  _ConversationRow(
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
                  label: const Text('New Chat'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PrismRelay.inkMuted,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 2, 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: PrismRelay.lilacSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 38,
                    child: PrismIcon(
                      PrismGlyph.chat,
                      size: 18,
                      color: PrismRelay.plum,
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
                            ?.copyWith(letterSpacing: -0.1),
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
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const PrismIcon(PrismGlyph.trash,
                      size: 19, color: PrismRelay.inkMuted),
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
            indent: 56,
            endIndent: 0,
            color: PrismRelay.line,
          ),
      ],
    );
  }
}
