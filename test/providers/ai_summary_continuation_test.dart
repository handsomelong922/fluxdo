import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// An unexpected provider call fails rather than silently using the network.
class _NoRequestsChatService implements AiChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Continue must not request AI: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AiChatStorageService storage;
  late TopicAiChatNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = AiChatStorageService(prefs);
    notifier = TopicAiChatNotifier(
      chatService: _NoRequestsChatService(),
      storageService: storage,
      topicId: 42,
    );
  });
  tearDown(() => notifier.dispose());

  test(
    'Continue seeds exact summary and title without an AI request',
    () async {
      await notifier.continueFromSummary(
        'Current topic',
        '**Summary**\n[2](#post-2)',
      );
      expect(notifier.state.isGenerating, isFalse);
      expect(notifier.state.messages.map((m) => m.role), [
        ChatRole.user,
        ChatRole.assistant,
      ]);
      expect(notifier.state.messages.first.content, contains('Current topic'));
      expect(notifier.state.messages.last.content, '**Summary**\n[2](#post-2)');
      final id = notifier.state.currentSessionId!;
      expect(
        storage.loadSessionMessages(id).last.content,
        '**Summary**\n[2](#post-2)',
      );
      expect(storage.getTopicSessions(42), hasLength(1));
    },
  );

  test(
    'private continuation stays memory-only through disposal save',
    () async {
      await notifier.continueFromSummary(
        'Private title',
        'Private summary',
        persistSession: false,
      );
      final id = notifier.state.currentSessionId!;
      expect(notifier.state.messages.last.content, 'Private summary');
      notifier.saveBeforeDispose();
      await Future<void>.delayed(Duration.zero);
      expect(storage.loadSessionMessages(id), isEmpty);
      expect(storage.getTopicSessions(42), isEmpty);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test('account reset removes private continuation and does not affect public chat', () async {
    await notifier.continueFromSummary(
      'Private title',
      'Private summary',
      persistSession: false,
    );
    notifier.discardMemoryOnlySession();
    expect(notifier.state.messages, isEmpty);
    expect(notifier.state.currentSessionId, isNull);
    notifier.saveBeforeDispose();
    expect(prefs.getKeys(), isEmpty);

    await notifier.continueFromSummary('Public title', 'Public summary');
    final publicId = notifier.state.currentSessionId;
    notifier.discardMemoryOnlySession();
    expect(notifier.state.currentSessionId, publicId);
    expect(notifier.state.messages.last.content, 'Public summary');
  });

  test('private and public continuation sessions remain isolated', () async {
    await notifier.continueFromSummary('Public title', 'Public summary');
    final publicId = notifier.state.currentSessionId!;
    await notifier.continueFromSummary(
      'Private title',
      'Private summary',
      persistSession: false,
    );
    final privateId = notifier.state.currentSessionId!;
    expect(privateId, isNot(publicId));
    notifier.switchSession(publicId);
    notifier.saveBeforeDispose();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.messages.last.content, 'Public summary');
    expect(storage.loadSessionMessages(privateId), isEmpty);
    expect(storage.getTopicSessions(42).map((s) => s.id), [publicId]);
  });

  test('empty summaries leave current conversation untouched', () async {
    await notifier.continueFromSummary('Title', 'Summary');
    final state = notifier.state;
    await notifier.continueFromSummary('Other title', ' \n ');
    expect(identical(notifier.state, state), isTrue);
  });
}
