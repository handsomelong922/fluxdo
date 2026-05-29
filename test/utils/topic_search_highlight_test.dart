import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/topic_search_highlight.dart';

void main() {
  group('TopicSearchHighlight', () {
    test('wraps matching text with mark tags', () {
      final html = TopicSearchHighlight.highlightHtml(
        '<p>Hello flutter, Flutter is nice.</p>',
        'flutter',
      );

      expect(
        html,
        contains('<mark class="topic-search-highlight">flutter</mark>'),
      );
      expect(
        html,
        contains('<mark class="topic-search-highlight">Flutter</mark>'),
      );
    });

    test('does not highlight code or pre text', () {
      final html = TopicSearchHighlight.highlightHtml(
        '<p>flutter</p><pre>flutter</pre><code>flutter</code>',
        'flutter',
      );

      expect(
        html,
        contains('<p><mark class="topic-search-highlight">flutter</mark></p>'),
      );
      expect(html, contains('<pre>flutter</pre>'));
      expect(html, contains('<code>flutter</code>'));
    });

    test('counts plain text matches case-insensitively', () {
      expect(
        TopicSearchHighlight.countPlainTextMatches(
          '<p>Foo foo <strong>FOO</strong></p>',
          'foo',
        ),
        3,
      );
    });
  });
}
