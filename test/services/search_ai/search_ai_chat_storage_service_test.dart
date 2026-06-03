import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/search_ai/search_ai_chat_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SearchAiChatStorageService', () {
    test('按搜索词保存并读取最新会话消息', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = SearchAiChatStorageService(prefs);

      await storage.saveSessionMessages(' Flutter   AI ', 'session-1', [
        AiChatMessage(
          id: 'u1',
          role: ChatRole.user,
          content: '怎么搜索插件',
          createdAt: DateTime.utc(2026),
        ),
        AiChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          content: '可以看这个帖子',
          createdAt: DateTime.utc(2026),
        ),
      ], title: '怎么搜索插件');

      final sessions = storage.getQuerySessions('flutter ai');

      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'session-1');
      expect(sessions.single.title, '怎么搜索插件');
      expect(storage.loadSessionMessages('session-1').map((m) => m.content), [
        '怎么搜索插件',
        '可以看这个帖子',
      ]);
    });

    test('删除会话后清理当前搜索词历史', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = SearchAiChatStorageService(prefs);

      await storage.saveSessionMessages('flutter', 'session-1', [
        AiChatMessage(
          id: 'u1',
          role: ChatRole.user,
          content: '问题',
          createdAt: DateTime.utc(2026),
        ),
      ]);

      await storage.deleteSession('flutter', 'session-1');

      expect(storage.getQuerySessions('flutter'), isEmpty);
      expect(storage.loadSessionMessages('session-1'), isEmpty);
    });
  });
}
