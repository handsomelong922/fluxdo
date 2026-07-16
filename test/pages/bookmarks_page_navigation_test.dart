import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/bookmarks_page.dart';

void main() {
  test('post bookmark keeps its explicit target even with OP preview', () {
    expect(
      resolveBookmarkDetailScrollTarget(
        bookmarkedPostNumber: 111,
        lastReadPostNumber: 80,
        hasFirstPostPreview: true,
      ),
      111,
    );
  });

  test('topic bookmark with OP preview starts from stable first post', () {
    expect(
      resolveBookmarkDetailScrollTarget(
        bookmarkedPostNumber: null,
        lastReadPostNumber: 80,
        hasFirstPostPreview: true,
      ),
      isNull,
    );
  });

  test('topic bookmark without preview preserves last read target', () {
    expect(
      resolveBookmarkDetailScrollTarget(
        bookmarkedPostNumber: null,
        lastReadPostNumber: 80,
        hasFirstPostPreview: false,
      ),
      80,
    );
  });
}
