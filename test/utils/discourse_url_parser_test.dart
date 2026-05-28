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
  });
}
