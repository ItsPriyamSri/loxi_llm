import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/prism_relay.dart';
import '../../../core/widgets/prism_icon.dart';
import '../../agent/agent_tool_catalog.dart';
import '../domain/app_settings.dart';
import 'settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final promptCount = notifier.savedPrompts().length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _SettingsGroup(
            title: 'Documents',
            children: [
              _InlineSlider(
                  setting: _NumericSetting.chunkSize,
                  settings: settings,
                  notifier: notifier),
              _InlineSlider(
                  setting: _NumericSetting.results,
                  settings: settings,
                  notifier: notifier),
            ],
          ),
          _SettingsGroup(
            title: 'Reading aloud',
            children: [
              _InlineSlider(
                  setting: _NumericSetting.speed,
                  settings: settings,
                  notifier: notifier),
            ],
          ),
          _SettingsGroup(
            title: 'Model',
            children: [
              _SettingRow(
                title: 'Generation',
                detail: 'Temperature, length and load settings',
                icon: PrismGlyph.graph,
                onTap: () => context.push('/generation'),
              ),
              _SettingRow(
                title: 'Prompt library',
                detail:
                    '$promptCount saved system ${promptCount == 1 ? 'prompt' : 'prompts'}',
                icon: PrismGlyph.book,
                tint: PrismRelay.peachSurface,
                ink: PrismRelay.amberInk,
                onTap: () => context.push('/prompts'),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Tools',
            children: [
              _SettingRow(
                title: 'Allowed tools',
                detail: 'What a supported model may call',
                icon: PrismGlyph.tools,
                tint: PrismRelay.peachSurface,
                ink: PrismRelay.amberInk,
                value: '${settings.enabledToolNames.length}',
                onTap: () => _showTools(context),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Diagnostics',
            children: [
              _SettingRow(
                title: 'Record model input and replies',
                detail:
                    'Stores full prompts and replies in unencrypted storage on this device. '
                    'Leave off for privacy.',
                icon: PrismGlyph.lock,
                trailing: Switch(
                  value: settings.modelIoLoggingEnabled,
                  onChanged: notifier.setModelIoLoggingEnabled,
                ),
              ),
              _SettingRow(
                title: 'Model I/O log',
                detail: settings.modelIoLoggingEnabled
                    ? 'Review recorded inputs and replies'
                    : 'Turn recording on to capture traces',
                icon: PrismGlyph.log,
                onTap: () => context.push('/model-io'),
              ),
              _SettingRow(
                title: 'Diagnostic logs',
                detail: 'App and inference activity',
                icon: PrismGlyph.log,
                tint: PrismRelay.line,
                ink: PrismRelay.inkSecondary,
                onTap: () => context.push('/logs'),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'About',
            children: [
              _SettingRow(
                title: 'How Loki works',
                detail: 'Offline, private, on this device',
                icon: PrismGlyph.lock,
                onTap: () => _howLokiWorks(context),
              ),
              _SettingRow(
                title: 'Open-source licenses',
                icon: PrismGlyph.link,
                tint: PrismRelay.line,
                ink: PrismRelay.inkSecondary,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Loki LLM',
                  applicationLegalese: '© 2026 Loki LLM authors · MIT License',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: PrismRelay.inkMuted,
                      fontSize: 12,
                      letterSpacing: 1.15,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            for (final row in children) ...[
              const Divider(height: 1),
              row,
            ],
          ],
        ),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.icon,
    this.detail,
    this.value,
    this.onTap,
    this.trailing,
    this.tint = PrismRelay.lilacSoft,
    this.ink = PrismRelay.plum,
  });

  final String title;
  final PrismGlyph icon;
  final String? detail;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color tint;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: SizedBox.square(
                  dimension: 38,
                  child: PrismIcon(icon, size: 18, color: ink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: type.titleSmall),
                    if (detail != null) Text(detail!, style: type.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Semantics(label: title, child: trailing),
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                if (value != null)
                  Text(
                    value!,
                    style: type.labelLarge?.copyWith(
                      color: PrismRelay.accent,
                      fontFeatures: PrismRelay.numbers,
                    ),
                  ),
                const SizedBox(width: 3),
                const PrismIcon(
                  PrismGlyph.chevron,
                  size: 15,
                  color: PrismRelay.inkMuted,
                  mirror: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _NumericSetting {
  chunkSize('Passage length', 100, 500, 8,
      helper: 'How much of your document Loki reads at once.'),
  results('Passages per answer', 1, 10, 9,
      helper: 'How many document passages Loki may use per answer.'),
  speed('Speed', .25, 1, 15, helper: null);

  const _NumericSetting(this.label, this.min, this.max, this.divisions,
      {required this.helper});

  final String label;
  final double min;
  final double max;
  final int divisions;
  final String? helper;

  double read(AppSettings settings) => switch (this) {
        chunkSize => settings.chunkSize.toDouble(),
        results => settings.topK.toDouble(),
        speed => settings.speechRate,
      };

  String format(double value) => this == speed
      ? '${(value / .5).toStringAsFixed(1)}×'
      : '${value.round()}';

  void save(SettingsNotifier notifier, double value) {
    switch (this) {
      case chunkSize:
        notifier.setChunkSize(value.round());
      case results:
        notifier.setTopK(value.round());
      case speed:
        notifier.setSpeechRate(value);
    }
  }
}

class _InlineSlider extends StatelessWidget {
  const _InlineSlider(
      {required this.setting, required this.settings, required this.notifier});

  final _NumericSetting setting;
  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final value = setting.read(settings);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(setting.label,
                    style: Theme.of(context).textTheme.titleSmall),
                if (setting.helper != null)
                  Text(setting.helper!,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
            Text(setting.format(value),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: PrismRelay.accent,
                    fontFeatures: PrismRelay.numbers)),
          ]),
          Semantics(
            label: setting.label,
            child: Slider(
              value: value,
              min: setting.min,
              max: setting.max,
              divisions: setting.divisions,
              label: setting.format(value),
              semanticFormatterCallback: setting.format,
              onChanged: (value) => setting.save(notifier, value),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showTools(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(settingsNotifierProvider);
        final notifier = ref.read(settingsNotifierProvider.notifier);
        return _SettingsSheet(
          title: 'Allowed tools',
          children: [
            for (final tool in kAgentToolCatalog)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tool.label),
                value: settings.enabledToolNames.contains(tool.name),
                onChanged: (enabled) =>
                    notifier.setToolEnabled(tool.name, enabled),
              ),
          ],
        );
      },
    ),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}


Future<void> _howLokiWorks(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How Loki works'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The model lives on your phone.'),
          SizedBox(height: 10),
          Text('Answers are generated on-device — nothing leaves your phone, even with no network.'),
          SizedBox(height: 10),
          Text('Download a model once and Loki works in airplane mode forever after.'),
          SizedBox(height: 10),
          Text('Unload the model from Models anytime to free memory.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
