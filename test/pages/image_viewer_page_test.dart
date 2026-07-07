import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/image_viewer_page.dart';

void main() {
  group('shouldUseInteractiveLoadingPreview', () {
    test('returns true when thumbnail differs from original image', () {
      expect(
        shouldUseInteractiveLoadingPreview(
          imageUrl: 'https://example.com/original.jpg',
          thumbnailUrl: 'https://example.com/thumbnail.jpg',
        ),
        isTrue,
      );
    });

    test('returns false when thumbnail is empty or identical', () {
      expect(
        shouldUseInteractiveLoadingPreview(
          imageUrl: 'https://example.com/original.jpg',
          thumbnailUrl: null,
        ),
        isFalse,
      );
      expect(
        shouldUseInteractiveLoadingPreview(
          imageUrl: 'https://example.com/original.jpg',
          thumbnailUrl: '   ',
        ),
        isFalse,
      );
      expect(
        shouldUseInteractiveLoadingPreview(
          imageUrl: 'https://example.com/original.jpg',
          thumbnailUrl: 'https://example.com/original.jpg',
        ),
        isFalse,
      );
    });
  });
}
