import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/chunked/chunked_html_content.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/chunked/html_chunk_cache.dart';

void main() {
  tearDown(() {
    HtmlChunkCache.instance.clear();
  });

  test('short html preload skips chunk cache work', () {
    const shortHtml = '<p>short reply</p>';

    ChunkedHtmlContent.preload(shortHtml);

    expect(HtmlChunkCache.instance.isCached(shortHtml), isFalse);
  });
}
