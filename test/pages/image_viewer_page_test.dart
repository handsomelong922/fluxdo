import 'package:flutter/widgets.dart';
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

  group('releaseImageViewerOriginalProviders', () {
    test('deduplicates providers and isolates eviction failures', () async {
      const first = AssetImage('first.png');
      const second = AssetImage('second.png');
      final attempted = <ImageProvider>[];

      final released = await releaseImageViewerOriginalProviders(
        const <ImageProvider>[first, first, second],
        evict: (provider) async {
          attempted.add(provider);
          if (provider == second) {
            throw StateError('eviction failed');
          }
          return true;
        },
      );

      expect(attempted, const <ImageProvider>[first, second]);
      expect(released, 1);
    });

    test('does not count providers absent from the memory cache', () async {
      const provider = AssetImage('missing.png');

      final released = await releaseImageViewerOriginalProviders(
        const <ImageProvider>[provider],
        evict: (_) async => false,
      );

      expect(released, 0);
    });
  });
}
