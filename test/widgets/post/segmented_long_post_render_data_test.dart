import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/post/post_item/segmented_long_post.dart';

void main() {
  tearDown(() {
    LongPostRenderData.clearCache();
  });

  test('LongPostRenderData reuses cached render data for identical html', () {
    const html = '<p>$_longChunk</p><p>$_longChunk</p>';

    final first = LongPostRenderData.fromHtml(html);
    final second = LongPostRenderData.fromHtml(html);

    expect(identical(first, second), isTrue);
  });
}

const String _longChunk =
    'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789'
    'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789'
    'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789'
    'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
