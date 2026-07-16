import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';

void main() {
  group('mergeRefreshedTopicHead', () {
    test('keeps refreshed head order and appends the existing tail', () {
      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const ['new-3', 'new-2', 'shared-1'],
        existing: const ['shared-1', 'old-4', 'old-5'],
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, ['new-3', 'new-2', 'shared-1', 'old-4', 'old-5']);
    });

    test('deduplicates repeated ids in both inputs', () {
      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const ['fresh-1', 'duplicate-1', 'fresh-2'],
        existing: const ['old-2', 'old-3', 'duplicate-3'],
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, ['fresh-1', 'fresh-2', 'old-3']);
    });

    test('returns a detached copy when refreshed head is empty', () {
      final existing = <String>['old-1', 'old-2'];

      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const [],
        existing: existing,
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, existing);
      expect(identical(merged, existing), isFalse);
    });
  });

  group('preserveRefreshedPagination', () {
    test('does not move the loaded page backwards after head refresh', () {
      final result = preserveRefreshedPagination(
        previousPage: 5,
        previousHasMore: false,
        refreshedPage: 0,
        refreshedHasMore: true,
      );

      expect(result.page, 5);
      expect(result.hasMore, isTrue);
    });

    test('keeps a newer refreshed page and combines has-more state', () {
      final result = preserveRefreshedPagination(
        previousPage: 1,
        previousHasMore: true,
        refreshedPage: 2,
        refreshedHasMore: false,
      );

      expect(result.page, 2);
      expect(result.hasMore, isTrue);
    });
  });
}
