import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/haptics.dart';
import '../theme/prism_relay.dart';
import '../widgets/prism_blocks.dart';
import '../widgets/prism_icon.dart';
import 'app_logger.dart';

/// Live, filterable view of [AppLogger] output. Reachable from Settings and
/// from the conversation screen, so crash diagnostics can be copied off-device.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  LogLevel? _minLevel;

  /// When true, show the persisted file (survives crashes/restarts) instead of
  /// the live in-memory buffer. Crash diagnosis needs the file view.
  bool _showFile = false;
  bool _readingFile = false;
  String _fileContents = '';

  bool _passesFilter(LogEntry e) =>
      _minLevel == null || e.level.index >= _minLevel!.index;

  Future<void> _loadFile() async {
    setState(() {
      _showFile = true;
      _readingFile = true;
    });
    final contents = await AppLogger.instance.readFile();
    if (mounted) {
      setState(() {
        _fileContents = contents;
        _readingFile = false;
      });
    }
  }

  Color _levelColor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.debug => scheme.outline,
      LogLevel.info => scheme.onSurface,
      LogLevel.warn => PrismRelay.amberInk,
      LogLevel.error => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showFile ? 'Logs (saved file)' : 'Logs (live)'),
        actions: [
          IconButton(
            icon: PrismIcon(_showFile ? PrismGlyph.log : PrismGlyph.clock),
            tooltip: _showFile
                ? 'Show live session'
                : 'Show saved file (survives crashes)',
            onPressed: _readingFile
                ? null
                : _showFile
                    ? () => setState(() => _showFile = false)
                    : _loadFile,
          ),
          if (!_showFile)
            PopupMenuButton<String>(
              tooltip: _minLevel == null
                  ? 'Filter level'
                  : 'Filter level (${_minLevel!.label}+)',
              // Accent while a filter hides some entries.
              icon: PrismIcon(PrismGlyph.filter,
                  color: _minLevel == null ? null : PrismRelay.accent),
              // String values: a null value never reaches onSelected, so
              // 'all' stands for no filter.
              onSelected: (level) => setState(
                  () => _minLevel = LogLevel.values.asNameMap()[level]),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'all', child: Text('All')),
                for (final level in LogLevel.values)
                  PopupMenuItem(
                      value: level.name, child: Text('${level.label}+')),
              ],
            ),
          IconButton(
            icon: const PrismIcon(PrismGlyph.copy),
            tooltip: 'Copy all',
            onPressed: _readingFile
                ? null
                : () async {
                    final text =
                        _showFile ? _fileContents : AppLogger.instance.dump();
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Logs copied to clipboard')),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const PrismIcon(PrismGlyph.trash),
            tooltip: 'Clear',
            onPressed: _readingFile
                ? null
                : () async {
                    final confirmed = await confirmDestructive(
                      context,
                      title: 'Clear logs?',
                      message: 'This permanently erases the diagnostic logs '
                          'on this device, including saved ones.',
                      confirmLabel: 'Clear',
                    );
                    if (!confirmed || !mounted) return;
                    Haptics.tap();
                    await AppLogger.instance.clear();
                    if (mounted) {
                      setState(() => _fileContents = '');
                    }
                  },
          ),
        ],
      ),
      body: _showFile ? _buildFileView(context) : _buildLiveView(context),
    );
  }

  Widget _buildFileView(BuildContext context) {
    if (_readingFile) return const Center(child: CircularProgressIndicator());
    if (_fileContents.startsWith(AppLogger.readFailurePrefix)) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PrismErrorBanner(
            message: 'Could not read saved logs.',
            retryTooltip: 'Read saved logs again',
            onRetry: _loadFile,
          ),
        ],
      );
    }
    if (_fileContents.isEmpty) {
      return ListView(children: const [
        PrismEmptyState(
          glyph: PrismGlyph.log,
          title: 'Saved log file is empty',
          message: 'Logs are written here as the app runs.',
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _fileContents,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveView(BuildContext context) {
    return StreamBuilder<LogEntry>(
      // Rebuild on every new entry; the buffer is the source of truth.
      stream: AppLogger.instance.stream,
      builder: (context, _) {
        final entries =
            AppLogger.instance.entries.where(_passesFilter).toList();
        if (entries.isEmpty) {
          return ListView(children: [
            AppLogger.instance.entries.isEmpty
                ? const PrismEmptyState(
                    glyph: PrismGlyph.log,
                    title: 'No logs yet',
                    message: 'App and inference activity shows up here.',
                  )
                : PrismEmptyState(
                    glyph: PrismGlyph.filter,
                    title: 'No matching logs',
                    message: 'Nothing at this level or above yet.',
                    actionLabel: 'Show all',
                    actionGlyph: PrismGlyph.filter,
                    onAction: () => setState(() => _minLevel = null),
                  ),
          ]);
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(20),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            // reverse: show newest at the bottom.
            final entry = entries[entries.length - 1 - index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(
                entry.format(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: _levelColor(context, entry.level),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
