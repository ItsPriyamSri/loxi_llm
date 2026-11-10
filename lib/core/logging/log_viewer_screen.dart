import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/haptics.dart';
import '../theme/prism_relay.dart';
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
              tooltip: 'Filter level',
              icon: const PrismIcon(PrismGlyph.log),
              onSelected: (level) => setState(() => _minLevel = LogLevel.values
                  .where((item) => item.name == level)
                  .firstOrNull),
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
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear logs?'),
                        content: const Text(
                            'This permanently erases the diagnostic logs on this device, including saved ones.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
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
    if (_fileContents.startsWith('Failed to read log file:')) {
      return Center(
          child: TextButton(
              onPressed: _loadFile,
              child: const Text('Could not read saved logs. Try again')));
    }
    if (_fileContents.isEmpty) {
      return const Center(child: Text('Saved log file is empty'));
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
          return Center(
            child: AppLogger.instance.entries.isEmpty
                ? const Text('No logs yet')
                : TextButton(
                    onPressed: () => setState(() => _minLevel = null),
                    child: const Text('No matching logs. Show all'),
                  ),
          );
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
