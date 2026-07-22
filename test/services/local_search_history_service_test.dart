import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/local_search_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('mergeLocalSearchHistory', () {
    test('trim 查询并按大小写不敏感去重后置顶', () {
      expect(
        mergeLocalSearchHistory(
          existing: const ['Dart', 'Flutter', 'Riverpod'],
          query: '  flutter  ',
          maxEntries: 10,
        ),
        const ['flutter', 'Dart', 'Riverpod'],
      );
    });

    test('忽略空白查询并限制最大条数', () {
      expect(
        mergeLocalSearchHistory(
          existing: const ['a', 'b', 'c'],
          query: '   ',
          maxEntries: 2,
        ),
        const ['a', 'b'],
      );
      expect(
        mergeLocalSearchHistory(
          existing: const ['a', 'b', 'c'],
          query: 'd',
          maxEntries: 3,
        ),
        const ['d', 'a', 'b'],
      );
    });
  });

  test('LocalSearchHistoryService 同步读取、保存并清空本地历史', () async {
    SharedPreferences.setMockInitialValues({
      LocalSearchHistoryService.storageKey: <String>['old query'],
    });
    final prefs = await SharedPreferences.getInstance();
    final service = LocalSearchHistoryService(prefs);

    expect(service.load(), const ['old query']);

    await service.save(const ['new query', 'old query']);
    expect(service.load(), const ['new query', 'old query']);

    await service.clear();
    expect(service.load(), isEmpty);
  });
}
