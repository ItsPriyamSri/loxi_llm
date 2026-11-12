import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loki_llm/core/theme/prism_relay.dart';
import 'package:loki_llm/features/documents/domain/document.dart';
import 'package:loki_llm/features/documents/presentation/documents_notifier.dart';
import 'package:loki_llm/features/documents/presentation/documents_screen.dart';

void main() {
  testWidgets('import keeps the library visible and restores Import on error', (
    tester,
  ) async {
    final notifier = _Library();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentsNotifierProvider.overrideWith(() => notifier)],
        child:
            MaterialApp(theme: PrismRelay.light, home: const DocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import document'));
    await tester.pump();

    expect(find.text('Importing…'), findsOneWidget);
    expect(find.text('Field notes.pdf'), findsOneWidget);
    final hero = find.byKey(const ValueKey('documents-hero'));
    expect(
        find.descendant(of: hero, matching: find.text('Importing…')),
        findsOneWidget);

    notifier.failImport();
    await tester.pumpAndSettle();
    expect(find.text('Field notes.pdf'), findsOneWidget);
    expect(find.text('The file exceeds the 10 MB limit.'), findsOneWidget);
    expect(find.text('Import document'), findsOneWidget);
  });
}

class _Library extends DocumentsNotifier {
  final _import = Completer<void>();

  @override
  Future<List<Document>> build() async => const [
        Document(
          id: 'first',
          name: 'Field notes.pdf',
          format: 'pdf',
          chunkCount: 7,
          createdAtMs: 1,
        ),
      ];

  @override
  Future<void> pickAndIngest() {
    state = const AsyncLoading();
    return _import.future;
  }

  void failImport() {
    state = const AsyncError(DocumentTooLargeException(), StackTrace.empty);
    _import.complete();
  }
}
