import 'package:flutter/services.dart';

/// Central haptic vocabulary so the app speaks with one accent.
///
/// Light taps for selection (dock, toggles, icon actions), a medium thump
/// for committing something in this moment (send, load model). All calls
/// are fire and forget and safe in tests (no-ops off-device).
abstract final class Haptics {
  static void selection() => HapticFeedback.selectionClick();

  static void tap() => HapticFeedback.lightImpact();

  static void commit() => HapticFeedback.mediumImpact();
}
