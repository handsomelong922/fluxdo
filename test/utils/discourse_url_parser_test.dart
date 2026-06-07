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

    test('ignores referral query parameters with spaces', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/topic/2293666?u = bbrother',
      );

      expect(info?.topicId, 2293666);
      expect(info?.slug, isNull);
      expect(info?.postNumber, isNull);
    });

    test('uses post fragment when malformed referral query is present', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/topic/2293666?u = bbrother#post_8',
      );

      expect(info?.topicId, 2293666);
      expect(info?.postNumber, 8);
    });

    test('keeps explicit post number when referral query is present', () {
      final info = DiscourseUrlParser.parseTopic(
        'https://linux.do/t/example-topic/2237130/9?u=4242',
      );

      expect(info?.topicId, 2237130);
      expect(info?.slug, 'example-topic');
      expect(info?.postNumber, 9);
    });

    test('parses id-only, last, base-path, and nested topic links', () {
      expect(
        DiscourseUrlParser.parseTopic(
          'https://linux.do/t/2237130/9',
        )?.postNumber,
        9,
      );
      expect(
        DiscourseUrlParser.parseTopic(
          'https://linux.do/t/2237130/last',
        )?.postNumber,
        isNull,
      );

      final basePath = DiscourseUrlParser.parseTopic(
        'https://example.com/forum/t/example-topic/2237130/9#post_7',
      );
      expect(basePath?.topicId, 2237130);
      expect(basePath?.slug, 'example-topic');
      expect(basePath?.postNumber, 9);

      final nested = DiscourseUrlParser.parseTopic(
        'https://linux.do/n/example-topic/2237130/context/12',
      );
      expect(nested?.topicId, 2237130);
      expect(nested?.slug, 'example-topic');
      expect(nested?.postNumber, 12);
      expect(nested?.isNestedRoute, isTrue);
    });

    test('parses canonical topic links and nested topic placeholder links', () {
      final nestedPlaceholder = DiscourseUrlParser.parseTopic(
        'https://linux.do/n/topic/388420?sort=old',
      );
      expect(nestedPlaceholder?.topicId, 388420);
      expect(nestedPlaceholder?.slug, isNull);
      expect(nestedPlaceholder?.postNumber, isNull);
      expect(nestedPlaceholder?.isNestedRoute, isTrue);

      final canonical = DiscourseUrlParser.parseTopic(
        'https://linux.do/topic/388420',
      );
      expect(canonical?.topicId, 388420);
      expect(canonical?.slug, isNull);
      expect(canonical?.postNumber, isNull);

      final canonicalPost = DiscourseUrlParser.parseTopic(
        'https://linux.do/topic/388420/7#post_8',
      );
      expect(canonicalPost?.topicId, 388420);
      expect(canonicalPost?.postNumber, 7);
    });

    test('canonicalizes complex topic links to stable topic paths', () {
      expect(
        DiscourseUrlParser.canonicalTopicPath(
          'https://linux.do/n/topic/388420?sort=old',
        ),
        '/topic/388420',
      );
      expect(
        DiscourseUrlParser.canonicalTopicPath(
          'https://linux.do/t/example-topic/388420/9?u=alice',
        ),
        '/topic/388420/9',
      );
    });

    test('does not treat topic API paths as topic links', () {
      expect(
        DiscourseUrlParser.parseTopic('https://linux.do/t/2237130/posts'),
        isNull,
      );
      expect(
        DiscourseUrlParser.parseTopic(
          'https://linux.do/t/example-topic/2237130/posts',
        ),
        isNull,
      );
      expect(
        DiscourseUrlParser.parseTopic(
          'https://linux.do/n/example-topic/2237130/posts',
        ),
        isNull,
      );
    });

    test('parses post short links separately', () {
      final info = DiscourseUrlParser.parsePostShortLink(
        'https://linux.do/p/987654/4242',
      );

      expect(info?.postId, 987654);
      expect(
        DiscourseUrlParser.parsePostShortLink('https://linux.do/p/987654/foo'),
        isNull,
      );
    });
  });
}
