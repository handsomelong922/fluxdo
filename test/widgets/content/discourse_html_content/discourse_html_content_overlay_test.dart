import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/discourse_html_content_widget.dart';

void main() {
  test('containsInlineCodeMarkup ignores fenced code blocks', () {
    const html = '<pre><code>final value = 1;</code></pre>';

    expect(DiscourseHtmlContent.containsInlineCodeMarkup(html), isFalse);
  });

  test('containsInlineCodeMarkup keeps inline code detection', () {
    const html = '<p>hello <code>world</code></p>';

    expect(DiscourseHtmlContent.containsInlineCodeMarkup(html), isTrue);
  });
}
