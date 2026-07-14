import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart';

void main() {
  group('rememberMountedBottomPageIds', () {
    test('keeps visited pages in lru order', () {
      final available = ['home', 'profile', 'bookmarks', 'history'];
      final mounted = rememberMountedBottomPageIds(
        mountedPageIds: ['home'],
        activePageId: 'bookmarks',
        availablePageIds: available,
        maxMountedPages: 4,
      );

      final next = rememberMountedBottomPageIds(
        mountedPageIds: mounted,
        activePageId: 'history',
        availablePageIds: available,
        maxMountedPages: 4,
      );

      expect(next.toList(), ['home', 'bookmarks', 'history']);
    });

    test('prunes least recently used page after reaching cap', () {
      final next = rememberMountedBottomPageIds(
        mountedPageIds: ['home', 'bookmarks', 'history'],
        activePageId: 'profile',
        availablePageIds: ['home', 'profile', 'bookmarks', 'history'],
        maxMountedPages: 3,
      );

      expect(next.toList(), ['bookmarks', 'history', 'profile']);
    });

    test('drops pages removed from available entries', () {
      final next = rememberMountedBottomPageIds(
        mountedPageIds: ['home', 'bookmarks', 'history'],
        activePageId: 'home',
        availablePageIds: ['home', 'profile'],
        maxMountedPages: 4,
      );

      expect(next.toList(), ['home']);
    });
  });

  group('shouldPruneMountedBottomPages', () {
    test('已经只保留当前页时不触发主树重建', () {
      expect(
        shouldPruneMountedBottomPages(
          mountedPageIds: const ['home'],
          activePageId: 'home',
        ),
        isFalse,
      );
    });

    test('仍有后台页或当前页不匹配时需要收缩', () {
      expect(
        shouldPruneMountedBottomPages(
          mountedPageIds: const ['home', 'bookmarks'],
          activePageId: 'bookmarks',
        ),
        isTrue,
      );
      expect(
        shouldPruneMountedBottomPages(
          mountedPageIds: const ['home'],
          activePageId: 'bookmarks',
        ),
        isTrue,
      );
    });
  });
}
