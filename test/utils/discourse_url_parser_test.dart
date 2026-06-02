import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/discourse_url_parser.dart';

void main() {
  group('DiscourseUrlParser.parseTopic', () {
    test('parses topic links with slug and post number', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/example-topic/12345/6?u=alice',
      );

      expect(info?.topicId, 12345);
      expect(info?.slug, 'example-topic');
      expect(info?.postNumber, 6);
    });

    test('uses post fragment as fallback post number', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/example-topic/12345#post_8',
      );

      expect(info?.topicId, 12345);
      expect(info?.postNumber, 8);
    });

    test('ignores referral query parameters on slug topic links', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/topic/2237130?u=4242',
      );

      expect(info?.topicId, 2237130);
      expect(info?.slug, isNull);
      expect(info?.postNumber, isNull);
    });

    test('keeps explicit post number when referral query is present', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/example-topic/2237130/9?u=4242',
      );

      expect(info?.topicId, 2237130);
      expect(info?.slug, 'example-topic');
      expect(info?.postNumber, 9);
    });
  });
}
