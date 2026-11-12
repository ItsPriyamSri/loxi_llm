import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_blocks.dart';
import '../../../core/widgets/prism_icon.dart';
import 'settings_notifier.dart';

class PromptLibraryScreen extends ConsumerWidget {
  const PromptLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final prompts = notifier.savedPrompts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompts'),
        actions: [
          IconButton(
            tooltip: 'Add prompt',
            onPressed: () {
              Haptics.tap();
              _editPrompt(context, notifier);
            },
            icon: const PrismIcon(PrismGlyph.plus),
          ),
        ],
      ),
      body: prompts.isEmpty
          ? ListView(children: [
              PrismEmptyState(
                glyph: PrismGlyph.book,
                title: 'No saved prompts',
                message: 'Save a system prompt once, reuse it in any chat.',
                actionLabel: 'Add a prompt',
                onAction: () {
                  Haptics.tap();
                  _editPrompt(context, notifier);
                },
              ),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              children: [
                const PrismSectionHeader(
                  'Library',
                  padding: EdgeInsets.fromLTRB(6, 10, 6, 6),
                ),
                for (var index = 0; index < prompts.length; index++)
                  _PromptRow(
                    prompt: prompts[index],
                    showDivider: index != prompts.length - 1,
                    onEdit: () => _editPrompt(
                      context,
                      notifier,
                      existing: prompts[index],
                    ),
                    onDelete: () async {
                      final confirmed = await confirmDestructive(
                        context,
                        title: 'Delete prompt?',
                        message: prompts[index].name,
                        confirmLabel: 'Delete',
                      );
                      if (confirmed && context.mounted) {
                        Haptics.tap();
                        notifier.deletePrompt(prompts[index].name);
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

Future<void> _editPrompt(
  BuildContext context,
  SettingsNotifier notifier, {
  SavedPrompt? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _PromptEditor(notifier: notifier, existing: existing),
  );
}

/// Asks for a library name. Stays open when the name is empty or already used.
Future<String?> askPromptName(
  BuildContext context, {
  required bool Function(String name) nameTaken,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PromptNameDialog(nameTaken: nameTaken),
  );
}

class _PromptEditor extends StatefulWidget {
  const _PromptEditor({required this.notifier, this.existing});

  final SettingsNotifier notifier;
  final SavedPrompt? existing;

  @override
  State<_PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<_PromptEditor> {
  late final TextEditingController _name;
  late final TextEditingController _body;
  var _error = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _body = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final taken = widget.notifier.savedPrompts().any(
          (prompt) =>
              prompt.name == name && prompt.name != widget.existing?.name,
        );
    if (taken) {
      setState(() => _error = 'That name is already used');
      return;
    }
    if (widget.existing != null && widget.existing!.name != name) {
      widget.notifier.deletePrompt(widget.existing!.name);
    }
    widget.notifier.savePrompt(name, _body.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.existing == null ? 'Add prompt' : 'Edit prompt'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'System prompt',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PromptNameDialog extends StatefulWidget {
  const _PromptNameDialog({required this.nameTaken});

  final bool Function(String name) nameTaken;

  @override
  State<_PromptNameDialog> createState() => _PromptNameDialogState();
}

class _PromptNameDialogState extends State<_PromptNameDialog> {
  final _name = TextEditingController();
  var _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Save to library'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Enter a name');
              return;
            }
            if (widget.nameTaken(name)) {
              setState(() => _error = 'That name is already used');
              return;
            }
            Navigator.pop(context, name);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.prompt,
    required this.onEdit,
    required this.onDelete,
    this.showDivider = true,
  });

  final SavedPrompt prompt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 2, 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: PrismRelay.lilacSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox.square(
                    dimension: 40,
                    child: PrismIcon(PrismGlyph.book,
                        size: 20, color: PrismRelay.plum),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prompt.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        prompt.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const PrismIcon(PrismGlyph.trash,
                      size: 19, color: PrismRelay.inkMuted),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 58,
            color: PrismRelay.line,
          ),
      ],
    );
  }
}
