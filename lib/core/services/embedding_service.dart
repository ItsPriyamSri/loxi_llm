import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:dart_wordpiece/dart_wordpiece.dart';

/// On-device embedding service using BGE-small-en-v1.5 INT8 ONNX.
///
/// Call [init] once before embedding. Provider handles lifecycle via [dispose].
///
/// BGE asymmetric usage:
/// - Queries:   [embedQuery]   — adds retrieval prefix automatically
/// - Passages:  [embedPassage] — no prefix (documents/chunks)
class EmbeddingService {
  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;

  bool get isInitialized => _session != null && _tokenizer != null;

  static const _queryPrefix =
      'Represent this sentence for searching relevant passages: ';
  static const _modelAsset = 'assets/models/bge-small-en-v1.5-int8.onnx';
  static const _vocabAsset = 'assets/vocab.txt';

  /// Load ONNX model and vocabulary from Flutter assets.
  /// Safe to call multiple times — idempotent after first init.
  Future<void> init() async {
    if (isInitialized) return;

    OrtEnv.instance.init(level: OrtLoggingLevel.warning);

    final modelBytes =
        (await rootBundle.load(_modelAsset)).buffer.asUint8List();
    _session = OrtSession.fromBuffer(modelBytes, OrtSessionOptions());

    final vocabText = await rootBundle.loadString(_vocabAsset);
    // BERT's 512-token limit; the default (64) cut most chunks short.
    _tokenizer = WordPieceTokenizer.fromString(
      vocabText,
      config: const TokenizerConfig(maxLength: 512),
    );
  }

  /// Embed a search query (adds BGE retrieval prefix).
  ///
  /// Returns a 384-dimensional L2-normalized vector.
  Future<List<double>> embedQuery(String text) =>
      _embed('$_queryPrefix$text');

  /// Embed a document passage (no prefix).
  ///
  /// Returns a 384-dimensional L2-normalized vector.
  Future<List<double>> embedPassage(String text) => _embed(text);

  Future<List<double>> _embed(String text) async {
    assert(isInitialized, 'EmbeddingService.init() must be called first');
    final tokens = _tokenizer!.encode(text);
    // The tokenizer pads to maxLength; run only the real tokens.
    final seqLen = tokens.realLength;

    final ortIds = OrtValueTensor.createTensorWithDataList(
        tokens.inputIdsInt64.sublist(0, seqLen), [1, seqLen]);
    final ortMask = OrtValueTensor.createTensorWithDataList(
        tokens.attentionMaskInt64.sublist(0, seqLen), [1, seqLen]);
    final ortTypes = OrtValueTensor.createTensorWithDataList(
        tokens.tokenTypeIdsInt64.sublist(0, seqLen), [1, seqLen]);
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session!.runAsync(runOptions, {
        'input_ids': ortIds,
        'attention_mask': ortMask,
        'token_type_ids': ortTypes,
      });
      // The model's only output is last_hidden_state [1, seq, 384].
      // BGE pools on the CLS token (position 0), then L2-normalizes. The
      // HNSW index uses Euclidean distance, which ranks like cosine only on
      // unit vectors.
      final hidden = outputs![0]!.value as List;
      final cls = ((hidden[0] as List)[0] as List).cast<double>();
      final norm = math.sqrt(cls.fold<double>(0, (s, x) => s + x * x));
      return List<double>.unmodifiable([for (final x in cls) x / norm]);
    } finally {
      ortIds.release();
      ortMask.release();
      ortTypes.release();
      runOptions.release();
      for (final e in outputs ?? const <OrtValue?>[]) {
        e?.release();
      }
    }
  }

  /// Release ORT resources. Called by provider's ref.onDispose.
  void dispose() {
    _session?.release();
    _session = null;
    _tokenizer = null;
  }
}

