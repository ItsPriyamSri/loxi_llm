import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_art.dart';
import '../../../core/widgets/prism_blocks.dart';
import '../../../core/widgets/prism_hero.dart';
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
            ? state.error is DocumentTooLargeException
                ? 'The file exceeds the 10 MB limit.'
                : 'Could not read the document library or complete the import.'
            : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          PrismHero(
            key: const ValueKey('documents-hero'),
            variant: PrismHeroVariant.mint,
            artwork: PrismArtwork.document,
            status: 'Document library',
            statusGlyph: PrismGlyph.file,
            announceStatus: false,
            title: 'Bring your own reading.',
            detail: const Text('Import a PDF, DOCX or TXT file up to 10 MB.'),
            actionLabel: importing ? 'Importing…' : 'Import document',
            actionGlyph: PrismGlyph.plus,
            actionEnabled: canImport,
            onAction: canImport ? _import : null,
          ),
          if (importing && !MediaQuery.disableAnimationsOf(context))
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 10, 2, 0),
              child: LinearProgressIndicator(
                minHeight: 5,
                borderRadius: BorderRadius.all(Radius.circular(6)),
                color: PrismRelay.greenInk,
                backgroundColor: PrismRelay.mintSurface,
              ),
            ),
          const SizedBox(height: 18),
          if (message != null)
            PrismErrorBanner(
              message: message,
              retryTooltip: 'Reload document library',
              onRetry: () {
                setState(() => _actionError = null);
                ref.invalidate(documentsNotifierProvider);
              },
            )
          else if (state.isLoading && !importing && _lastDocuments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!state.isLoading && _lastDocuments.isEmpty)
            const _EmptyLibrary(),
          if (_lastDocuments.isNotEmpty) ...[
            const PrismSectionHeader(
              'Imported documents',
              padding: EdgeInsets.fromLTRB(6, 16, 6, 4),
            ),
            const SizedBox(height: 2),
          ],
          for (var index = 0; index < _lastDocuments.length; index++) ...[
            _DocumentRow(
              key: ValueKey('document-${_lastDocuments[index].id}'),
              index: index,
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

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    super.key,
    required this.index,
    required this.document,
    required this.canDelete,
    required this.onDelete,
    this.showDivider = true,
  });

  final int index;
  final Document document;
  final bool canDelete;
  final Future<void> Function(Document document) onDelete;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final (tileBg, tileInk) = PrismRelay.identityTile(index);
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
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: PrismIcon(PrismGlyph.file,
                        size: 20, color: tileInk),
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
                        '${document.format.toUpperCase()} · ${document.chunkCount} chunks',
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
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: PrismRelay.mintSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const SizedBox.square(
              dimension: 52,
              child: PrismIcon(PrismGlyph.file,
                  size: 24, color: PrismRelay.greenInk),
            ),
          ),
          const SizedBox(height: 12),
          Text('Nothing imported yet',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Your PDFs and notes will show up here with their chunk counts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
