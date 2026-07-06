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
}
