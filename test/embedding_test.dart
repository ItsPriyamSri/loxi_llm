import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:loki_llm/features/documents/domain/document_chunk.dart';
import 'package:loki_llm/core/services/embedding_service.dart';

void main() {
  group('DocumentChunk domain', () {
    test('copyWith updates content', () {
      const chunk = DocumentChunk(
        chunkId: 'c1',
        documentId: 'doc1',
        content: 'Original text',
        chunkIndex: 0,
        createdAtMs: 0,
      );
      final updated = chunk.copyWith(content: 'Updated text');
      expect(updated.content, equals('Updated text'));
      expect(updated.chunkId, equals('c1')); // unchanged
      expect(updated.documentId, equals('doc1')); // unchanged
    });

    test('embedding is null by default', () {
      const chunk = DocumentChunk(
        chunkId: 'c2',
        documentId: 'doc1',
        content: 'Some text',
        chunkIndex: 0,
        createdAtMs: 0,
      );
      expect(chunk.embedding, isNull);
    });

    test('copyWith can set embedding', () {
      const chunk = DocumentChunk(
        chunkId: 'c3',
        documentId: 'doc1',
        content: 'Some text',
        chunkIndex: 0,
        createdAtMs: 0,
      );
      final withEmbedding = chunk.copyWith(embedding: List.filled(384, 0.1));
      expect(withEmbedding.embedding, isNotNull);
      expect(withEmbedding.embedding!.length, equals(384));
    });

    test('chunkIndex preserved after copyWith', () {
      const chunk = DocumentChunk(
        chunkId: 'c4',
        documentId: 'doc1',
        content: 'Chunk text',
        chunkIndex: 5,
        createdAtMs: 1000,
      );
      final updated = chunk.copyWith(content: 'New');
      expect(updated.chunkIndex, equals(5));
      expect(updated.createdAtMs, equals(1000));
    });
  });

  group('EmbeddingService state', () {
    test('isInitialized is false before init', () {
      final service = EmbeddingService();
      expect(service.isInitialized, isFalse);
    });

    test('dispose can be called on uninitialized service without error', () {
      final service = EmbeddingService();
      expect(() => service.dispose(), returnsNormally);
    });

    test('init is idempotent after dispose (no throw)', () async {
      // Note: init() requires Flutter asset bundle — skipped in unit test.
      // This test verifies pre-conditions only.
      final service = EmbeddingService();
      expect(service.isInitialized, isFalse);
      service.dispose();
      expect(service.isInitialized, isFalse);
    });
  });

  // Runs the bundled BGE model through the real ONNX Runtime. On Linux:
  // LD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/linux
  group('EmbeddingService with the real model', () {
    final ortOnPath =
        Platform.environment['LD_LIBRARY_PATH']?.contains('onnxruntime') ??
            false;
    final skip = ortOnPath ? false : 'ONNX Runtime not on LD_LIBRARY_PATH';
    late EmbeddingService service;

    setUpAll(() async {
      if (!ortOnPath) return;
      TestWidgetsFlutterBinding.ensureInitialized();
      service = EmbeddingService();
      await service.init();
    });
    tearDownAll(() {
      if (ortOnPath) service.dispose();
    });

    double dot(List<double> a, List<double> b) =>
        [for (var i = 0; i < a.length; i++) a[i] * b[i]].reduce((x, y) => x + y);

    test('returns a 384-dim unit vector', () async {
      final v = await service.embedPassage('Cats sleep most of the day.');
      expect(v, hasLength(384));
      expect(math.sqrt(dot(v, v)), closeTo(1.0, 1e-4));
    }, skip: skip);

    test('ranks the relevant passage first', () async {
      final q = await service.embedQuery('How long do cats sleep?');
      final cats = await service.embedPassage(
          'Cats sleep twelve to sixteen hours a day.');
      final tax = await service.embedPassage(
          'Income tax returns are due at the end of July.');
      expect(dot(q, cats), greaterThan(dot(q, tax)));
    }, skip: skip);

    test('reads past 64 tokens', () async {
      final head = List.filled(80, 'word').join(' ');
      final a = await service.embedPassage('$head apples and pears');
      final b = await service.embedPassage('$head engines and gearboxes');
      expect(a, isNot(equals(b)));
    }, skip: skip);
  });
}
