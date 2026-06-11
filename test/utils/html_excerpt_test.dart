import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/html_excerpt.dart';

void main() {
  group('cleanHtmlExcerpt', () {
    test('strips html tags and decodes common entities', () {
      final result = cleanHtmlExcerpt(
        '<p>Hello&nbsp;<strong>Linux.do</strong>&hellip;</p>'
        '<p>&lt;tag&gt; &amp; &#39;quote&#39;</p>',
      );

      expect(result, "Hello Linux.do... <tag> & 'quote'");
    });
  });
}
