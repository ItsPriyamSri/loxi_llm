import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:loki_llm/core/providers/objectbox_provider.dart';
import 'package:loki_llm/core/platform/flutter_tts_service.dart';
import 'package:loki_llm/core/providers/shared_preferences_provider.dart';
import 'package:loki_llm/core/providers/tts_provider.dart';
import 'package:loki_llm/core/router/app_router.dart';
import 'package:loki_llm/core/services/tts_service.dart';
import 'package:loki_llm/core/theme/prism_relay.dart';
import 'package:loki_llm/features/chat/data/conversation_repository.dart';
import 'package:loki_llm/features/chat/data/message_repository.dart';
import 'package:loki_llm/features/chat/domain/conversation.dart';
import 'package:loki_llm/features/chat/domain/message.dart';
import 'package:loki_llm/features/chat/domain/message_role.dart';
import 'package:loki_llm/features/chat/presentation/conversation_screen.dart';
import 'package:loki_llm/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterTtsService', () {
    test('pause keeps the sentence when the engine accepts it', () async {
      final engine = _Engine();
      final service = FlutterTtsService(tts: engine);

      await service.speak('**Hello**');
      expect(await service.pause(), isTrue);
      await service.resume();

      expect(engine.spoken, ['Hello', 'Hello']);
      expect(engine.stops, 1);
    });

    test('a refused pause stops instead of pretending to pause', () async {
      final engine = _Engine()..pauseResult = 0;
      final service = FlutterTtsService(tts: engine);

      await service.speak('Hello');
      expect(await service.pause(), isFalse);
      await service.resume();

      expect(engine.spoken, ['Hello']);
      expect(engine.stops, 2);
    });

    test('pause during startup keeps speak from starting', () async {
      final engine = _Engine()..holdRate = Completer<void>();
      final service = FlutterTtsService(tts: engine);

      final pending = service.speak('Hello');
      await Future<void>.delayed(Duration.zero);
      expect(await service.pause(), isTrue);
      engine.holdRate!.complete();
      await pending;

      expect(engine.spoken, isEmpty);
    });
  });

  testWidgets('applying a saved prompt swaps the centered controls',
      (tester) async {
    final container = await _openChat(_FakeTts(), blank: true);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    // Before selection: the template grid owns the screen center and the
    // shortcuts ride above the composer.
    expect(find.byKey(const ValueKey('saved-prompts')), findsOneWidget);
    expect(find.byKey(const ValueKey('centered-shortcuts')), findsNothing);
    final quick = find.byKey(const ValueKey('quick-shortcuts'));
    expect(find.descendant(of: quick, matching: find.text('Translate')),
        findsOneWidget);
    await tester.tap(find.text('Concise'));
    await tester.pumpAndSettle();
    // After selection: the grid yields and the shortcuts take the center.
    expect(find.byKey(const ValueKey('saved-prompts')), findsNothing);
    expect(find.byKey(const ValueKey('quick-shortcuts')), findsNothing);
    expect(find.text('Concise'), findsNothing);
    final shortcuts = find.byKey(const ValueKey('centered-shortcuts'));
    expect(find.descendant(of: shortcuts, matching: find.text('Translate')),
        findsOneWidget);
    expect(find.byTooltip('System prompt'), findsOneWidget);
  });

  testWidgets('the shortcut row hides while the keyboard is up',
      (tester) async {
    addTearDown(tester.view.reset);
    final container = await _openChat(_FakeTts(), blank: true);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    final quick = find.byKey(const ValueKey('quick-shortcuts'));
    expect(quick, findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(quick, findsNothing);
  });

  testWidgets('composer controls remain reachable at 200% with the keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await _openChat(_FakeTts(), blank: true);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    // Open the add-to-message sheet and toggle Documents from it.
    await tester.tap(find.byKey(const ValueKey('add-to-message')));
    await tester.pumpAndSettle();
    final docsRow = find.text('Documents');
    expect(docsRow.hitTestable(), findsOneWidget);
    final before = tester.widget<Switch>(find.byType(Switch).first).value;
    await tester.tap(docsRow);
    await tester.pumpAndSettle();
    final after = tester.widget<Switch>(find.byType(Switch).first).value;
    expect(after, isNot(before));
    // Tools stay visible but greyed when the model cannot call them.
    expect(find.text('Tools'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1)); // dismiss sheet via barrier
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('send-stop')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock keeps a conversation draft through a Models round trip',
      (tester) async {
    final container = await _openChat(_FakeTts(), blank: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/chat/c1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft for the local model');

    final dock = find.byKey(const ValueKey('prism-dock'));
    await tester.tap(find.descendant(of: dock, matching: find.text('Models')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dock, matching: find.text('Chat')));
    await tester.pumpAndSettle();

    expect(find.text('Draft for the local model'), findsOneWidget);
    expect(find.byTooltip('System prompt'), findsOneWidget);
  });

  group('read aloud on a conversation', () {
    testWidgets('leaving the chat stops reading', (tester) async {
      final tts = _FakeTts();
      final container = await _openChat(tts);
      await tester.pumpWidget(_app(container));
      await tester.pump();

      await tester.tap(find.byTooltip('Read aloud').first);
      await tester.pump();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ));
      expect(tts.calls, ['speak', 'stop']);

      tts.speakGate!.complete();
      await tester.pump();
    });

    testWidgets('pause then resume', (tester) async {
      final tts = _FakeTts();
      final container = await _openChat(tts);
      await tester.pumpWidget(_app(container));
      await tester.pump();

      await tester.tap(find.byTooltip('Read aloud').first);
      await tester.pump();
      expect(find.byTooltip('Pause reading'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause reading'));
      await tester.pump();
      expect(find.byTooltip('Resume reading'), findsOneWidget);

      await tester.tap(find.byTooltip('Resume reading'));
      await tester.pump();
      expect(tts.calls, ['speak', 'pause', 'resume']);

      tts.speakGate!.complete();
      await tester.pump();
    });

    testWidgets('starting another reply stops the first from owning the button',
        (tester) async {
      final tts = _FakeTts();
      final container = await _openChat(tts);
      await tester.pumpWidget(_app(container));
      await tester.pump();

      await tester.tap(find.byTooltip('Read aloud').first);
      await tester.pump();
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();

      expect(tts.spoken, ['alpha', 'beta']);
      expect(find.byTooltip('Pause reading'), findsOneWidget);
      tts.speakGate!.complete();
      await tester.pump();
    });

    testWidgets('a refused pause returns the button to speak', (tester) async {
      final tts = _FakeTts()..pauseOk = false;
      final container = await _openChat(tts);
      await tester.pumpWidget(_app(container));
      await tester.pump();

      await tester.tap(find.byTooltip('Read aloud').first);
      await tester.pump();
      await tester.tap(find.byTooltip('Pause reading'));
      await tester.pump();

      expect(find.byTooltip('Resume reading'), findsNothing);
      expect(find.byTooltip('Read aloud'), findsNWidgets(2));
      tts.speakGate!.complete();
      await tester.pump();
    });
  });
}

class _Engine extends FlutterTts {
  int pauseResult = 1;
  int stops = 0;
  final spoken = <String>[];
  Completer<void>? holdRate;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {}

  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    final hold = holdRate;
    if (hold != null) await hold.future;
    return 1;
  }

  @override
  Future<dynamic> pause() async => pauseResult;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }
}

final class _FakeTts implements TtsService {
  bool pauseOk = true;
  final calls = <String>[];
  final spoken = <String>[];
  Completer<void>? speakGate = Completer<void>();

  @override
  bool get isSupported => true;

  @override
  Future<void> speak(String text, {double rate = 0.5}) async {
    calls.add('speak');
    spoken.add(text);
    final gate = speakGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<bool> pause() async {
    calls.add('pause');
    return pauseOk;
  }

  @override
  Future<void> resume({double rate = 0.5}) async {
    calls.add('resume');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {}
}

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: PrismRelay.light,
        home: const ConversationScreen(conversationId: 'c1')),
  );
}

Future<ProviderContainer> _openChat(_FakeTts tts, {bool blank = false}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    if (blank)
      'settings_prompt_library': '[{"name":"Concise","body":"Keep it brief."}]',
  });
  final prefs = await SharedPreferences.getInstance();
  final conversations = _MemoryConversations()
    ..save(const Conversation(
      id: 'c1',
      title: 'Chat',
      createdAtMs: 1,
      updatedAtMs: 1,
    ));
  final messages = _MemoryMessages();
  if (!blank) {
    messages
      ..save(const Message(
        id: 'a',
        conversationId: 'c1',
        role: MessageRole.assistant,
        content: 'alpha',
        createdAtMs: 1,
      ))
      ..save(const Message(
        id: 'b',
        conversationId: 'c1',
        role: MessageRole.assistant,
        content: 'beta',
        createdAtMs: 2,
      ));
  }
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      objectBoxStoreProvider
          .overrideWith((_) => throw UnimplementedError('No store in test')),
      ttsServiceProvider.overrideWithValue(tts),
      conversationRepositoryProvider.overrideWith((ref) => conversations),
      messageRepositoryProvider.overrideWith((ref) => messages),
    ],
  );
  addTearDown(container.dispose);
  return container;
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
    return _items.values
        .where((message) => message.conversationId == conversationId)
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  @override
  void save(Message message) => _items[message.id] = message;

  @override
  void deleteByConversationId(String conversationId) {
    _items
        .removeWhere((_, message) => message.conversationId == conversationId);
  }
}
