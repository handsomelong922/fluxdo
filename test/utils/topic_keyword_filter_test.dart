import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/utils/topic_keyword_filter.dart';

Topic _topic(int id, String title) => Topic(
  id: id,
  title: title,
  slug: 'topic-$id',
  postsCount: 1,
  replyCount: 0,
  views: 0,
  likeCount: 0,
  categoryId: '1',
);

void main() {
  group('TopicKeywordFilter.apply', () {
    test('分页复用关键词缓存后，仍重新检查正则结果和标题更新', () {
      final rules = List.generate(1000, (i) => 'keyword_$i');
      final topics = [_topic(1, '正常话题'), _topic(2, 'keyword_999')];
      final matches = <String, bool>{};
      TopicFilterResult inspect(List<Topic> input) =>
          TopicKeywordFilter.inspect(
            input,
            normalizedKeywords: rules,
            wholeWord: true,
            regexPatterns: const ['正常'],
            regexMatches: matches,
          );
      final pending = inspect(topics);
      expect(pending.pending.map((t) => t.id), [1]);
      expect(pending.hidden.single.keyword, 'keyword_999');
      matches['正常话题'] = true;
      final settled = inspect([...topics, _topic(3, '新增话题')]);
      expect(settled.hidden.map((t) => t.reason), [
        TopicFilterReason.regex,
        TopicFilterReason.keyword,
      ]);
      expect(settled.pending.map((t) => t.id), [3]);
      matches['修改后的话题'] = false;
      expect(inspect([_topic(2, '修改后的话题')]).visible.single.id, 2);
      rules[999] = 'replacement';
      matches['keyword_999'] = false;
      expect(inspect(topics).visible.single.id, 2);
    });

    test('仅正则也生效，完整词开关不改变显式表达式语义', () {
      final input = [_topic(20, '求助手机 AI'), _topic(21, '其他话题')];
      for (final wholeWord in [false, true]) {
        final (visible, hidden, byUser) = TopicKeywordFilter.apply(
          input,
          normalizedKeywords: const [],
          wholeWord: wholeWord,
          regexPatterns: const ['(求助|提问).*(手机|电脑)'],
          regexMatches: const {'求助手机 AI': true, '其他话题': false},
        );
        expect(visible.map((topic) => topic.id), [21]);
        expect(hidden, 1);
        expect(byUser, 0);
      }
    });

    test('未验证标题保持隐藏，字面规则不受影响', () {
      final input = [_topic(20, 'a.b'), _topic(21, 'axb'), _topic(22, 'AI')];
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        input,
        normalizedKeywords: const ['a.b'],
        wholeWord: false,
        regexPatterns: const [r'^AI$'],
        regexMatches: const {'axb': false},
      );
      expect(visible.map((topic) => topic.id), [21]);
      expect(hidden, 1); // 未知正则结果属于待验证，不算命中。
      expect(
        () => TopicKeywordFilter.apply(
          input,
          normalizedKeywords: const [],
          wholeWord: false,
          regexPatterns: const ['['],
        ),
        throwsStateError,
      );
    });

    final topics = [
      _topic(1, 'Main thread for the AI release'),
      _topic(2, '今天的水帖合集'),
      _topic(3, 'Available tools'),
      _topic(4, 'Hello world'),
      _topic(5, 'AI 助手测试'),
    ];

    test('空关键词返回原列表，hidden 为 0', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const [],
        wholeWord: false,
      );
      expect(visible, same(topics));
      expect(hidden, 0);
    });

    test('空话题列表直接返回，hidden 为 0', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        const [],
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      expect(visible, isEmpty);
      expect(hidden, 0);
    });

    test('子串匹配不区分大小写', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      // 子串模式下 "ai" 命中 Main、Available、AI、AI 助手 → 4 条被过滤
      // 仅 id=2 "今天的水帖合集" 与 id=4 "Hello world" 留下
      // 等等：Hello world 不含 ai，Main 含 ai (m-a-i-n)，Available 含 ai (av-ai-lable)
      // AI release 含 ai，AI 助手 含 ai
      expect(visible.map((t) => t.id), [2, 4]);
      expect(hidden, 3);
    });

    test('中文关键词命中', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['水帖'],
        wholeWord: false,
      );
      expect(visible.map((t) => t.id), [1, 3, 4, 5]);
      expect(hidden, 1);
    });

    test('多关键词任一命中即过滤', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai', '水帖'],
        wholeWord: false,
      );
      // 命中：1(ai)、2(水帖)、3(ai)、5(ai) → 剩 4
      expect(visible.map((t) => t.id), [4]);
      expect(hidden, 4);
    });

    test('完整词模式下英文不再误匹配子串', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai'],
        wholeWord: true,
      );
      // 完整词下 "ai" 应命中 "AI release"（独立的 AI 词）和 "AI 助手"
      // 而不命中 "Main"（mai 是 main 的子串）和 "Available"（ai 是 av-ai-lable 的子串）
      expect(visible.map((t) => t.id), containsAll([2, 3, 4]));
      expect(visible.map((t) => t.id), isNot(contains(1)));
      expect(visible.map((t) => t.id), isNot(contains(5)));
      expect(hidden, 2);
    });

    test('完整词模式对中文关键词等价于子串', () {
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['水帖'],
        wholeWord: true,
      );
      expect(visible.map((t) => t.id), [1, 3, 4, 5]);
      expect(hidden, 1);
    });

    test('包含特殊正则字符的关键词被转义', () {
      final special = [
        _topic(10, 'Use a.b.c notation'),
        _topic(11, 'No dots here'),
      ];
      final (visible, hidden, _) = TopicKeywordFilter.apply(
        special,
        normalizedKeywords: const ['a.b.c'],
        wholeWord: false,
      );
      expect(visible.map((t) => t.id), [11]);
      expect(hidden, 1);
    });
  });

  group('confirmed filter snapshot', () {
    test('blocked then literal then regex precedence; pending is separate', () {
      final blocked = Topic(
        id: 30,
        title: 'AI blocked',
        slug: 'blocked',
        postsCount: 1,
        replyCount: 0,
        views: 0,
        likeCount: 0,
        categoryId: '1',
        posters: [
          TopicPoster(
            userId: 7,
            description: '',
            extras: '',
            user: TopicUser(id: 7, username: 'Alice', avatarTemplate: ''),
          ),
        ],
      );
      final result = TopicKeywordFilter.inspect(
        [
          blocked,
          _topic(31, 'AI literal'),
          _topic(32, 'regex'),
          _topic(33, 'pending'),
          _topic(34, 'visible'),
          blocked,
        ],
        normalizedKeywords: const ['ai'],
        wholeWord: true,
        blockedUsernames: const {'alice'},
        regexPatterns: const ['.*'],
        regexMatches: const {
          'AI literal': true,
          'regex': true,
          'visible': false,
        },
      );
      expect(result.hidden.map((e) => e.topic.id), [30, 31, 32]);
      expect(result.hidden.map((e) => e.reason), [
        TopicFilterReason.blockedUser,
        TopicFilterReason.keyword,
        TopicFilterReason.regex,
      ]);
      expect(result.hidden[1].keyword, 'ai');
      expect(result.hiddenByBlocked, 1);
      expect(result.pending.map((e) => e.id), [33]);
      expect(result.visible.map((e) => e.id), [34]);
      expect(() => result.hidden.clear(), throwsUnsupportedError);
    });

    test(
      'pending transitions to confirmed or visible without inflating count',
      () {
        final input = [_topic(1, 'hide'), _topic(2, 'show')];
        TopicFilterResult inspect(Map<String, bool> matches) =>
            TopicKeywordFilter.inspect(
              input,
              normalizedKeywords: const [],
              wholeWord: false,
              regexPatterns: const ['^hide'],
              regexMatches: matches,
            );
        final pending = inspect({});
        expect(pending.hidden, isEmpty);
        expect(pending.pending, hasLength(2));
        final settled = inspect({'hide': true, 'show': false});
        expect(settled.hidden, hasLength(1));
        expect(settled.visible.single.id, 2);
        expect(settled.pending, isEmpty);
        expect(pending.pending, hasLength(2)); // 旧快照保持不变。
      },
    );

    test(
      'disabled filters preserve provider list identity for index caches',
      () {
        final input = [_topic(1, 'visible')];
        final result = TopicKeywordFilter.inspect(
          input,
          normalizedKeywords: const [],
          wholeWord: false,
        );
        expect(result.visible, same(input));
        expect(result.hidden, isEmpty);
        expect(
          () => result.hidden.add(
            FilteredTopic(input.first, TopicFilterReason.regex),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('duplicate IDs cannot inflate the banner count', () {
      final topic = _topic(1, 'AI');
      final result = TopicKeywordFilter.inspect(
        [topic, topic],
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      final (_, count, _) = TopicKeywordFilter.apply(
        [topic, topic],
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      expect(count, result.hidden.length);
      expect(count, 1);
    });
  });

  group('TopicKeywordFilter.shouldAutoLoadMore', () {
    test('hasMore 为 false 时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 5,
          visibleAfter: 5,
          hasMore: false,
          attempts: 0,
        ),
        isFalse,
      );
    });

    test('达到 maxAttempts 时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 0,
          visibleAfter: 0,
          hasMore: true,
          attempts: 3,
        ),
        isFalse,
      );
    });

    test('可见增量足够时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 10,
          visibleAfter: 25,
          hasMore: true,
          attempts: 0,
        ),
        isFalse,
      );
    });

    test('可见增量不足且未达上限且仍有更多时续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 10,
          visibleAfter: 12,
          hasMore: true,
          attempts: 1,
        ),
        isTrue,
      );
    });
  });
}
