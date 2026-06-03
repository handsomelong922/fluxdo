import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/search_ai/search_ai_assistant_service.dart';

void main() {
  group('SearchAiAssistantService', () {
    const provider = AiProvider(
      id: 'provider-1',
      name: 'Provider',
      type: AiProviderType.gemini,
      baseUrl: 'https://example.com',
      models: [AiModel(id: 'model-1')],
    );

    const model = AiModel(
      id: 'model-1',
      features: AiModelFeatureConfig(webSearchEnabled: true),
    );

    test('构建论坛上下文时读取主题详情、清理 HTML 并限制内容长度', () async {
      final forum = _FakeForumGateway(
        searchResult: SearchResult(
          posts: [
            _searchPost(
              id: 10,
              topicId: 101,
              postNumber: 2,
              blurb: '<span class="search-highlight">Flutter</span> 相关摘要',
            ),
          ],
          users: const [],
          groupedResult: GroupedSearchResult(
            term: 'flutter',
            morePosts: false,
            moreUsers: false,
            moreCategories: false,
            moreFullPageResults: false,
          ),
        ),
        details: {
          101: _topicDetail(
            id: 101,
            title: 'Flutter 搜索优化',
            posts: [
              _post(id: 1, topicId: 101, postNumber: 1, cooked: '<p>首楼内容</p>'),
              _post(
                id: 2,
                topicId: 101,
                postNumber: 2,
                cooked: '<p>命中楼层 <strong>重点</strong></p>',
              ),
              _post(
                id: 3,
                topicId: 101,
                postNumber: 3,
                cooked: '<p>${List.filled(800, '长内容').join()}</p>',
              ),
            ],
          ),
        },
      );
      final service = SearchAiAssistantService(
        chatService: _FakeAiChatService(),
        forumGateway: forum,
      );

      final context = await service.loadForumContext(
        query: 'flutter',
        visiblePosts: const [],
        maxTopics: 1,
        maxPostsPerTopic: 3,
        maxCharsPerPost: 80,
      );

      expect(forum.searchedQueries, ['flutter']);
      expect(forum.loadedTopicIds, [101]);
      expect(context.topics.single.title, 'Flutter 搜索优化');
      expect(context.topics.single.posts.map((p) => p.postNumber), [1, 2, 3]);
      expect(context.toPromptText(), contains('首楼内容'));
      expect(context.toPromptText(), contains('命中楼层 重点'));
      expect(context.toPromptText(), isNot(contains('<strong>')));
      expect(context.toPromptText().length, lessThan(900));
    });

    test('主题详情读取失败时保留搜索摘要作为降级上下文', () async {
      final forum = _FakeForumGateway(
        searchResult: SearchResult(
          posts: [
            _searchPost(
              id: 10,
              topicId: 101,
              postNumber: 1,
              blurb: '<p>只剩搜索摘要</p>',
            ),
          ],
          users: const [],
          groupedResult: GroupedSearchResult(
            term: 'flutter',
            morePosts: false,
            moreUsers: false,
            moreCategories: false,
            moreFullPageResults: false,
          ),
        ),
        details: const {},
      );
      final service = SearchAiAssistantService(
        chatService: _FakeAiChatService(),
        forumGateway: forum,
      );

      final context = await service.loadForumContext(query: 'flutter');

      expect(context.topics.single.posts.single.content, '只剩搜索摘要');
      expect(context.topics.single.detailLoadFailed, isTrue);
    });

    test('主题详情未包含命中楼层时保留搜索命中摘要', () async {
      final forum = _FakeForumGateway(
        searchResult: SearchResult(
          posts: [
            _searchPost(
              id: 99,
              topicId: 101,
              postNumber: 9,
              blurb: '<p>远处命中内容</p>',
            ),
          ],
          users: const [],
          groupedResult: GroupedSearchResult(
            term: 'flutter',
            morePosts: false,
            moreUsers: false,
            moreCategories: false,
            moreFullPageResults: false,
          ),
        ),
        details: {
          101: _topicDetail(
            id: 101,
            title: 'Flutter 搜索优化',
            posts: [
              _post(id: 1, topicId: 101, postNumber: 1, cooked: '<p>首楼</p>'),
              _post(id: 2, topicId: 101, postNumber: 2, cooked: '<p>二楼</p>'),
              _post(id: 3, topicId: 101, postNumber: 3, cooked: '<p>三楼</p>'),
            ],
          ),
        },
      );
      final service = SearchAiAssistantService(
        chatService: _FakeAiChatService(),
        forumGateway: forum,
      );

      final context = await service.loadForumContext(
        query: 'flutter',
        maxTopics: 1,
        maxPostsPerTopic: 3,
      );

      expect(context.topics.single.posts.map((p) => p.postNumber), [1, 9, 2]);
      expect(context.toPromptText(), contains('搜索命中楼层：#9'));
      expect(context.toPromptText(), contains('远处命中内容'));
    });

    test('生成引用链接时 slug 缺失则使用 id-only 话题链接', () async {
      final forum = _FakeForumGateway(
        searchResult: SearchResult(
          posts: [
            _searchPost(
              id: 10,
              topicId: 101,
              postNumber: 2,
              blurb: '摘要',
              slug: '',
            ),
          ],
          users: const [],
          groupedResult: GroupedSearchResult(
            term: 'flutter',
            morePosts: false,
            moreUsers: false,
            moreCategories: false,
            moreFullPageResults: false,
          ),
        ),
        details: {
          101: _topicDetail(
            id: 101,
            title: 'Flutter 搜索优化',
            slug: '',
            posts: [_post(id: 1, topicId: 101, postNumber: 1, cooked: '正文')],
          ),
        },
      );
      final service = SearchAiAssistantService(
        chatService: _FakeAiChatService(),
        forumGateway: forum,
      );

      final context = await service.loadForumContext(
        query: 'flutter',
        maxTopics: 1,
      );

      expect(context.topics.single.url, 'https://linux.do/t/101/2');
    });

    test('发送搜索对话时复用当前模型并关闭外部 web search', () async {
      String? capturedSystemPrompt;
      List<Map<String, String>>? capturedMessages;
      AiModelFeatureConfig? capturedFeatureConfig;
      final forum = _FakeForumGateway(
        searchResult: SearchResult(
          posts: [
            _searchPost(id: 10, topicId: 101, postNumber: 1, blurb: '摘要'),
          ],
          users: const [],
          groupedResult: GroupedSearchResult(
            term: 'flutter',
            morePosts: false,
            moreUsers: false,
            moreCategories: false,
            moreFullPageResults: false,
          ),
        ),
        details: {
          101: _topicDetail(
            id: 101,
            title: 'Flutter 搜索优化',
            posts: [_post(id: 1, topicId: 101, postNumber: 1, cooked: '正文')],
          ),
        },
      );
      final service = SearchAiAssistantService(
        chatService: _FakeAiChatService(
          onSend:
              ({
                required systemPrompt,
                required messages,
                required featureConfig,
              }) {
                capturedSystemPrompt = systemPrompt;
                capturedMessages = messages;
                capturedFeatureConfig = featureConfig;
                return Stream<String>.fromIterable(['回答']);
              },
        ),
        forumGateway: forum,
      );

      final chunks = await service
          .sendSearchChat(
            provider: provider,
            model: model,
            apiKey: 'secret',
            searchQuery: 'flutter',
            userMessage: '帮我找相关帖子',
            searchAssistantPrompt: '请优先按相关度排序。',
            history: [
              AiChatMessage(
                id: 'm1',
                role: ChatRole.assistant,
                content: '上一轮回答',
                createdAt: DateTime.utc(2026),
              ),
            ],
          )
          .toList();

      expect(chunks.join(), '回答');
      expect(capturedSystemPrompt, contains('当前搜索词：flutter'));
      expect(capturedSystemPrompt, contains('不能编造'));
      expect(capturedSystemPrompt, contains('标准 Markdown'));
      expect(capturedSystemPrompt, contains('请优先按相关度排序。'));
      expect(capturedMessages?.first['content'], contains('论坛检索上下文'));
      expect(capturedMessages?.first['cache'], 'true');
      expect(capturedMessages?.last['content'], '帮我找相关帖子');
      expect(capturedFeatureConfig?.webSearchEnabled, isFalse);
    });
  });
}

SearchPost _searchPost({
  required int id,
  required int topicId,
  required int postNumber,
  required String blurb,
  String? slug,
}) {
  return SearchPost(
    id: id,
    username: 'alice',
    avatarTemplate: '',
    createdAt: DateTime.utc(2026),
    likeCount: 3,
    blurb: blurb,
    postNumber: postNumber,
    topic: SearchTopic(
      id: topicId,
      title: '搜索结果标题 $topicId',
      slug: slug ?? 'topic-$topicId',
      categoryId: 1,
      tags: const [],
      postsCount: 3,
      views: 10,
      closed: false,
      archived: false,
    ),
  );
}

TopicDetail _topicDetail({
  required int id,
  required String title,
  required List<Post> posts,
  String? slug,
}) {
  return TopicDetail(
    id: id,
    title: title,
    slug: slug ?? 'topic-$id',
    postsCount: posts.length,
    postStream: PostStream(
      posts: posts,
      stream: posts.map((p) => p.id).toList(),
    ),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}

Post _post({
  required int id,
  required int topicId,
  required int postNumber,
  required String cooked,
}) {
  return Post(
    id: id,
    topicId: topicId,
    username: 'alice',
    avatarTemplate: '',
    cooked: cooked,
    postNumber: postNumber,
    postType: 1,
    updatedAt: DateTime.utc(2026),
    createdAt: DateTime.utc(2026),
    likeCount: 0,
    replyCount: 0,
  );
}

class _FakeForumGateway implements SearchAiForumGateway {
  _FakeForumGateway({required this.searchResult, required this.details});

  final SearchResult searchResult;
  final Map<int, TopicDetail> details;
  final searchedQueries = <String>[];
  final loadedTopicIds = <int>[];

  @override
  Future<SearchResult> search({required String query}) async {
    searchedQueries.add(query);
    return searchResult;
  }

  @override
  Future<TopicDetail> getTopicDetail(int topicId) async {
    loadedTopicIds.add(topicId);
    final detail = details[topicId];
    if (detail == null) throw StateError('not found');
    return detail;
  }
}

typedef _FakeSend =
    Stream<String> Function({
      required String? systemPrompt,
      required List<Map<String, String>> messages,
      required AiModelFeatureConfig featureConfig,
    });

class _FakeAiChatService extends AiChatService {
  _FakeAiChatService({this.onSend});

  final _FakeSend? onSend;

  @override
  Stream<String> sendChatStream({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
    AiModelFeatureConfig featureConfig = const AiModelFeatureConfig(),
  }) {
    return onSend?.call(
          systemPrompt: systemPrompt,
          messages: messages,
          featureConfig: featureConfig,
        ) ??
        const Stream<String>.empty();
  }
}
