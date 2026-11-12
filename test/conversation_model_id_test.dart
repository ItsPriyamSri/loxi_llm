import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loki_llm/core/engine/inference_backend.dart';
import 'package:loki_llm/core/platform/no_op_tts_service.dart';
import 'package:loki_llm/core/providers/inference_provider.dart';
import 'package:loki_llm/core/providers/shared_preferences_provider.dart';
import 'package:loki_llm/core/providers/tts_provider.dart';
import 'package:loki_llm/features/chat/data/conversation_repository.dart';
import 'package:loki_llm/features/chat/data/message_repository.dart';
import 'package:loki_llm/features/chat/domain/conversation.dart';
import 'package:loki_llm/features/chat/domain/message.dart';
import 'package:loki_llm/features/chat/domain/message_role.dart';
import 'package:loki_llm/features/chat/presentation/chat_notifier.dart';
import 'package:loki_llm/features/chat/presentation/chat_screen.dart';
import 'package:loki_llm/features/chat/presentation/conversation_screen.dart';
import 'package:loki_llm/features/chat/presentation/conversation_list_notifier.dart';
import 'package:loki_llm/features/models/domain/model.dart';
import 'package:loki_llm/features/models/domain/model_status.dart';
import 'package:loki_llm/features/models/presentation/models_notifier.dart';
import 'package:loki_llm/features/models/presentation/models_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phi3 = Model(
  id: 'phi3-mini-4k-q4km',
  name: 'Phi-3 Mini',
  sizeLabel: '2 GB',
  sizeBytes: 1,
);

void main() {
  group('Conversation model id', () {
    Future<ProviderContainer> openContainer({
      InferenceBackend? backend,
      Model? loaded,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ttsServiceProvider.overrideWithValue(NoOpTtsService()),
          modelsNotifierProvider.overrideWith(_Catalog.new),
          conversationRepositoryProvider.overrideWith(
            (ref) => _MemoryConversations(),
          ),
          messageRepositoryProvider.overrideWith((ref) => _MemoryMessages()),
          inferenceNotifierProvider.overrideWith(
            () => _FixedInference(backend: backend, loaded: loaded),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(inferenceNotifierProvider.future);
      return container;
    }

    String? storedModelId(ProviderContainer container, String id) {
      return container
          .read(conversationRepositoryProvider)
          .getById(id)
          ?.modelId;
    }

    testWidgets('a new chat stores the loaded model id', (tester) async {
      final container = await openContainer(
        backend: _ReadyBackend(),
        loaded: _phi3,
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const ChatScreen()),
          GoRoute(
            path: '/chat/:id',
            builder: (_, __) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();

      final stored = container.read(conversationRepositoryProvider).getAll();
      expect(stored, hasLength(1));
      expect(stored.single.modelId, _phi3.id);
    });

    testWidgets('the ready model hero opens a chat attributed to that model',
        (tester) async {
      final container =
          await openContainer(backend: _ReadyBackend(), loaded: _phi3);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const ModelsScreen()),
          GoRoute(
              path: '/chat/:id',
              builder: (_, __) => const Scaffold(body: Text('Chat opened'))),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start a chat'));
      await tester.pumpAndSettle();

      expect(find.text('Chat opened'), findsOneWidget);
      final chats = container.read(conversationRepositoryProvider).getAll();
      expect(chats.single.modelId, _phi3.id);
    });

    testWidgets('Stop before the first token keeps the saved user turn',
        (tester) async {
      final container =
          await openContainer(backend: _HoldBackend(), loaded: _phi3);
      final id = container
          .read(conversationListNotifierProvider.notifier)
          .createConversation();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ConversationScreen(conversationId: id)),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Check the first token');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      // The thinking dots repeat until the first token, so the frame never
      // settles; pump past the send instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Thinking…'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop generating'));
      await tester.runAsync(() => _idleChat(container, id));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(find.text('Thinking…'), findsNothing);
      final messages =
          container.read(messageRepositoryProvider).getMessages(id);
      expect(
          messages
              .where((message) => message.role == MessageRole.user)
              .single
              .content,
          'Check the first token');
      expect(find.text('No reply generated. Try sending again.'), findsOneWidget);
      expect(find.byTooltip('Read aloud'), findsNothing);
    });

    test('send stores the answering model when generation fails', () async {
      final container = await openContainer(backend: _ErrorBackend());
      final id = container
          .read(conversationListNotifierProvider.notifier)
          .createConversation();
      container.read(inferenceNotifierProvider.notifier).loadedModel = _phi3;
      final sub = container.listen(chatNotifierProvider(id), (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(chatNotifierProvider(id).notifier);
      await container.read(chatNotifierProvider(id).future);

      await notifier.send('hi');
      final chat = await _idleChat(container, id);

      expect(chat.error, isNotNull);
      expect(storedModelId(container, id), _phi3.id);
    });

    test('send stores the answering model when the reply is stopped', () async {
      final container = await openContainer(backend: _HoldBackend());
      final id = container
          .read(conversationListNotifierProvider.notifier)
          .createConversation();
      container.read(inferenceNotifierProvider.notifier).loadedModel = _phi3;
      final sub = container.listen(chatNotifierProvider(id), (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(chatNotifierProvider(id).notifier);
      await container.read(chatNotifierProvider(id).future);

      await notifier.send('hi');
      await notifier.stop();
      final chat = await _idleChat(container, id);

      expect(chat.error, isNull);
      expect(storedModelId(container, id), _phi3.id);
    });
  });
}

Future<ChatState> _idleChat(ProviderContainer container, String id) async {
  for (var i = 0; i < 20; i++) {
    final chat = container.read(chatNotifierProvider(id)).valueOrNull;
    if (chat != null && !chat.isStreaming) return chat;
    await Future<void>.delayed(Duration.zero);
  }
  fail('chat did not finish');
}

class _Catalog extends ModelsNotifier {
  @override
  Future<List<Model>> build() async => [
        _phi3.copyWith(status: ModelStatus.loaded, localPath: '/tmp/phi3.gguf'),
      ];
}

class _FixedInference extends InferenceNotifier {
  _FixedInference({this.backend, this.loaded});

  final InferenceBackend? backend;
  final Model? loaded;

  @override
  Future<InferenceBackend?> build() async {
    loadedModel = loaded;
    return backend;
  }
}

final class _MemoryConversations implements ConversationRepository {
  final _items = <String, Conversation>{};

  @override
  List<Conversation> getAll() => _items.values.toList();

  @override
  Conversation? getById(String conversationId) => _items[conversationId];

  @override
  void save(Conversation conversation) =>
      _items[conversation.id] = conversation;

  @override
  void delete(String conversationId) => _items.remove(conversationId);
}

final class _MemoryMessages implements MessageRepository {
  final _items = <String, Message>{};

  @override
  List<Message> getMessages(String conversationId) {
    final messages = _items.values
        .where((message) => message.conversationId == conversationId)
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    return messages;
  }

  @override
  void save(Message message) => _items[message.id] = message;

  @override
  void deleteByConversationId(String conversationId) {
    _items
        .removeWhere((_, message) => message.conversationId == conversationId);
  }
}

final class _ReadyBackend extends InferenceBackend {
  @override
  bool get isLoaded => true;
}

final class _ErrorBackend extends InferenceBackend {
  @override
  bool get isLoaded => true;

  @override
  Stream<String> generate(
    String prompt, {
    List<String> stopSequences = const [],
    String? grammar,
    List<String> imagePaths = const [],
    int maxTokens = 512,
    double temperature = 0.7,
    int topK = 40,
    double topP = 0.95,
    double repeatPenalty = 1.1,
  }) =>
      Stream.error(StateError('failed'));
}

final class _HoldBackend extends InferenceBackend {
  final _gate = Completer<void>();

  @override
  bool get isLoaded => true;

  @override
  Future<void> stop() async {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Stream<String> generate(
    String prompt, {
    List<String> stopSequences = const [],
    String? grammar,
    List<String> imagePaths = const [],
    int maxTokens = 512,
    double temperature = 0.7,
    int topK = 40,
    double topP = 0.95,
    double repeatPenalty = 1.1,
  }) async* {
    await _gate.future;
  }
}
