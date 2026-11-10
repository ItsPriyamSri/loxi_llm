import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_icon.dart';
import '../domain/document.dart';
import 'documents_notifier.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  List<Document> _lastDocuments = const [];
  bool _pickerOpen = false;
  bool _deleting = false;
  String? _actionError;

  Future<void> _import() async {
    Haptics.tap();
    setState(() {
      _pickerOpen = true;
      _actionError = null;
    });
    try {
      await ref.read(documentsNotifierProvider.notifier).pickAndIngest();
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Could not open the file picker.');
      }
    } finally {
      if (mounted) setState(() => _pickerOpen = false);
    }
  }

  Future<void> _delete(Document document) async {
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove document?'),
          content: Text(document.name),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove')),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        Haptics.tap();
        await ref
            .read(documentsNotifierProvider.notifier)
            .deleteDocument(document.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Could not remove the document.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentsNotifierProvider);
    final data = state.valueOrNull;
    if (data != null) _lastDocuments = data;
    final importing = _pickerOpen && state.isLoading;
    final canImport = !_pickerOpen && !_deleting && !state.isLoading;
    final message = _actionError ??
        (state.hasError
            ? state.error == 'File too large (max 10 MB)'
                ? 'The file exceeds the 10 MB limit.'
                : 'Could not read the document library or complete the import.'
            : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Document library',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('PDF, DOCX or TXT',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                FilledButton.icon(
                  onPressed: canImport ? _import : null,
                  icon: const PrismIcon(PrismGlyph.plus),
                  label: Text(importing ? 'Importing…' : 'Import'),
                ),
              ],
            ),
          ),
          if (importing)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: MediaQuery.disableAnimationsOf(context)
                  ? const SizedBox.shrink()
                  : const LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                      color: PrismRelay.amberInk,
                      backgroundColor: PrismRelay.peachSurface,
                    ),
            ),
          const SizedBox(height: 20),
          if (message != null)
            _ErrorBanner(
              message: message,
              onRetry: () {
                setState(() => _actionError = null);
                ref.invalidate(documentsNotifierProvider);
              },
            )
          else if (state.isLoading && !importing && _lastDocuments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator(
                color: PrismRelay.accent,
              )),
            )
          else if (!state.isLoading && _lastDocuments.isEmpty)
            const _EmptyLibrary(),
          if (_lastDocuments.isNotEmpty) ...[
            const _SectionHeader('Library'),
            const SizedBox(height: 2),
          ],
          for (var index = 0; index < _lastDocuments.length; index++) ...[
            _DocumentRow(
              document: _lastDocuments[index],
              canDelete: canImport,
              onDelete: _delete,
              showDivider: index != _lastDocuments.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 4),
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

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.canDelete,
    required this.onDelete,
    this.showDivider = true,
  });

  final Document document;
  final bool canDelete;
  final Future<void> Function(Document document) onDelete;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Tooltip(
          message: document.name,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 2, 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: PrismRelay.mintSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox.square(
                    dimension: 40,
                    child: PrismIcon(PrismGlyph.file,
                        size: 20, color: PrismRelay.greenInk),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${document.format.toUpperCase()} · ${document.chunkCount} passages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PrismRelay.inkMuted,
                              fontSize: 12.5,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove document',
                  onPressed: canDelete ? () => onDelete(document) : null,
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: PrismRelay.mintSurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const SizedBox.square(
              dimension: 64,
              child: PrismIcon(PrismGlyph.file,
                  size: 28, color: PrismRelay.greenInk),
            ),
          ),
          const SizedBox(height: 14),
          Text('No documents yet',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Import a PDF, DOCX or TXT to use it in chat.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PrismRelay.blush,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3C4C4)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          const PrismIcon(PrismGlyph.warn, size: 20, color: PrismRelay.errorInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PrismRelay.errorInk,
                    fontSize: 13,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Reload document library',
            onPressed: onRetry,
            icon: const PrismIcon(PrismGlyph.refresh,
                size: 20, color: PrismRelay.errorInk),
          ),
        ],
      ),
    );
  }
}
