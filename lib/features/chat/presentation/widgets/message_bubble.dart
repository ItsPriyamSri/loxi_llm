import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/prism_relay.dart';
import '../../../../core/widgets/prism_icon.dart';
import 'chat_markdown_text.dart';
import 'image_attachment_thumbnail.dart';

/// Speed and wait for the bottom row of a finished reply.
///
/// [speed] is the model call. [time] is the whole wait from send.
({String? speed, String time})? replyStats({
  required int? tokenCount,
  required int? totalDurationMs,
  required int? timeToFirstTokenMs,
  int? replyWaitMs,
}) {
  final shownMs = replyWaitMs ?? totalDurationMs;
  if (shownMs == null) return null;
  final time = '${(shownMs / 1000).toStringAsFixed(1)} s';
  final speedMs = totalDurationMs;
  if (tokenCount == null ||
      timeToFirstTokenMs == null ||
      speedMs == null ||
      tokenCount < 2) {
    return (speed: null, time: time);
  }
  final decodeMs = speedMs - timeToFirstTokenMs;
  if (decodeMs <= 0) return (speed: null, time: time);
  final tps = (tokenCount - 1) * 1000 / decodeMs;
  return (speed: '${tps.toStringAsFixed(1)} tok/s', time: time);
}

/// A single chat message bubble with optional copy / read-aloud actions.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    this.content,
    this.child,
    this.imagePath,
    required this.isUser,
    required this.isStreaming,
    this.onCopy,
    this.onReadAloud,
    this.onStopReadAloud,
    this.isSpeaking = false,
    this.isPaused = false,
    this.speedLabel,
    this.timeLabel,
  }) : assert(content != null || child != null,
            'Provide either content or child');

  final String? content;
  final Widget? child;

  /// Path to an image attached to this message, if any.
  final String? imagePath;
  final bool isUser;
  final bool isStreaming;
  final VoidCallback? onCopy;
  final VoidCallback? onReadAloud;
  final VoidCallback? onStopReadAloud;

  /// When true, the read-aloud button shows pause.
  final bool isSpeaking;

  /// When true, the read-aloud button shows resume.
  final bool isPaused;

  /// Model speed, shown at the bottom only after the reply is saved.
  final String? speedLabel;

  /// Whole wait from send, on the same bottom row as [speedLabel].
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    const statColor = PrismRelay.inkMuted;
    final showFooter = !isStreaming &&
        (speedLabel != null ||
            timeLabel != null ||
            onCopy != null ||
            onReadAloud != null ||
            onStopReadAloud != null);

    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: isUser ? MediaQuery.sizeOf(context).width * .82 : 640,
        ),
        decoration: BoxDecoration(
          color: isUser ? PrismRelay.lilacSoft : PrismRelay.surface,
          border: Border.all(
              color: isUser ? PrismRelay.lilacBorder : PrismRelay.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: PrismBrandMark(size: 19),
              ),
            if (imagePath != null) ...[
              ImageAttachmentThumbnail(path: imagePath!, size: 200),
              const SizedBox(height: 8),
            ],
            if (child != null || (content?.isNotEmpty ?? false))
              child ??
                  ChatMarkdownText(
                    content!,
                    style: const TextStyle(
                        color: PrismRelay.ink, fontSize: 15, height: 1.5),
                    isStreaming: isStreaming,
                  ),
            if (showFooter) ...[
              const SizedBox(height: 2),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (speedLabel != null)
                    Text(
                      speedLabel!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: statColor),
                    ),
                  if (timeLabel != null) ...[
                    if (speedLabel != null) const SizedBox(width: 8),
                    Text(
                      timeLabel!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: statColor),
                    ),
                  ],
                  if (onCopy != null)
                    _ActionIcon(
                      icon: PrismGlyph.copy,
                      tooltip: 'Copy message',
                      onPressed: onCopy!,
                      color: PrismRelay.inkSecondary,
                    ),
                  if (onReadAloud != null)
                    _ActionIcon(
                      icon: isPaused
                          ? PrismGlyph.play
                          : isSpeaking
                              ? PrismGlyph.pause
                              : PrismGlyph.audio,
                      tooltip: isPaused
                          ? 'Resume reading'
                          : isSpeaking
                              ? 'Pause reading'
                              : 'Read aloud',
                      onPressed: onReadAloud!,
                      color: PrismRelay.inkSecondary,
                    ),
                  if (onStopReadAloud != null)
                    _ActionIcon(
                      icon: PrismGlyph.stop,
                      tooltip: 'Stop reading',
                      onPressed: onStopReadAloud!,
                      color: PrismRelay.inkSecondary,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatefulWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
  });

  final PrismGlyph icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon> {
  bool _justCopied = false;

  static const _flash = Duration(milliseconds: 1400);

  @override
  Widget build(BuildContext context) {
    // The copy affordance acknowledges the tap by morphing into a check.
    final morph = widget.icon == PrismGlyph.copy;
    final shownGlyph = morph && _justCopied ? PrismGlyph.check : widget.icon;
    final shownTooltip = morph && _justCopied ? 'Copied' : widget.tooltip;
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween(begin: .6, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: PrismIcon(
          shownGlyph,
          key: ValueKey(shownGlyph),
          size: 17,
          color: morph && _justCopied ? PrismRelay.greenInk : widget.color,
        ),
      ),
      tooltip: shownTooltip,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      color: widget.color,
      onPressed: () {
        widget.onPressed();
        Haptics.selection();
        if (!morph || _justCopied) return;
        setState(() => _justCopied = true);
        Future<void>.delayed(_flash, () {
          if (mounted) setState(() => _justCopied = false);
        });
      },
    );
  }
}
