import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/services/notion/notion_config.dart';

Future<NotionConfigRepository> _repository() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return NotionConfigRepository(prefs);
}

NotionConfig _config(String suffix) {
  return NotionConfig(
    integrationToken: 'secret_$suffix',
    databaseId: 'database_$suffix',
    autoSyncOnBookmark: true,
    syncScope: NotionSyncScope.firstPostOnly,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fallback 配置可在账号未解析时读取', () async {
    final repository = await _repository();
    final config = _config('fallback');

    await repository.write(NotionConfigRepository.fallbackAccountId, config);

    final loaded = repository.readFallback();
    expect(loaded.integrationToken, 'secret_fallback');
    expect(loaded.databaseId, 'database_fallback');
    expect(loaded.autoSyncOnBookmark, isTrue);
    expect(loaded.syncScope, NotionSyncScope.firstPostOnly);
  });

  test('readFallback 优先读取最近账号配置', () async {
    final repository = await _repository();

    await repository.write('alice', _config('alice'));

    expect(repository.readFallback().integrationToken, 'secret_alice');
  });

  test('clearFallbackSources 会清理兜底和最近账号配置', () async {
    final repository = await _repository();

    await repository.write(
      NotionConfigRepository.fallbackAccountId,
      _config('fallback'),
    );
    await repository.write('alice', _config('alice'));

    await repository.clearFallbackSources();

    expect(
      repository.read(NotionConfigRepository.fallbackAccountId).hasStoredValues,
      isFalse,
    );
    expect(repository.read('alice').hasStoredValues, isFalse);
    expect(repository.readFallback().hasStoredValues, isFalse);
  });
}
