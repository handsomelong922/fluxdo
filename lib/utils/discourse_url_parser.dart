import 'url_parse_utils.dart';

/// 话题链接解析结果
class TopicLinkInfo {
  final int topicId;
  final String? slug;
  final int? postNumber;
  final bool isNestedRoute;

  const TopicLinkInfo({
    required this.topicId,
    this.slug,
    this.postNumber,
    this.isNestedRoute = false,
  });
}

/// 帖子短链接解析结果（Discourse `/p/<post_id>`）
class PostShortLinkInfo {
  final int postId;

  const PostShortLinkInfo({required this.postId});
}

/// 用户链接解析结果
class UserLinkInfo {
  final String username;

  const UserLinkInfo({required this.username});
}

class DiscourseUrlParser {
  DiscourseUrlParser._();

  /// 用户链接格式：/u/username
  static final _userRegex = RegExp(r'/u/([^/?#]+)', caseSensitive: false);

  static final _postFragmentRegex = RegExp(
    r'^post[-_]?(\d+)$',
    caseSensitive: false,
  );

  /// 解析话题链接，返回 [TopicLinkInfo] 或 null
  ///
  /// 支持格式：
  /// - `/t/12345` → topicId=12345
  /// - `/t/12345/1` → topicId=12345, postNumber=1
  /// - `/t/topic-slug/12345` → topicId=12345, slug=topic-slug
  /// - `/t/topic-slug/12345/1` → topicId=12345, slug=topic-slug, postNumber=1
  /// - `/t/topic-slug/12345/last` → topicId=12345
  /// - `/n/topic-slug/12345/1` → topicId=12345, slug=topic-slug, postNumber=1
  /// - `/topic/12345` → topicId=12345
  /// - `/topic/12345/1` → topicId=12345, postNumber=1
  static TopicLinkInfo? parseTopic(String url) {
    final segments = _pathSegments(url);
    final topicIndex = _lastIndexOfAny(segments, const {'t', 'n'});
    if (topicIndex >= 0 && topicIndex + 1 < segments.length) {
      final marker = segments[topicIndex].toLowerCase();
      final parsed = marker == 'n'
          ? _parseNestedTopic(segments, topicIndex, url)
          : _parseRegularTopic(segments, topicIndex, url);
      if (parsed != null) return parsed;
    }

    final canonicalTopicIndex = _lastIndexOfAny(segments, const {'topic'});
    if (canonicalTopicIndex < 0 || canonicalTopicIndex + 1 >= segments.length) {
      return null;
    }
    return _parseCanonicalTopic(segments, canonicalTopicIndex, url);
  }

  /// 将任意可识别的话题链接转为稳定的通用路径。
  ///
  /// 例如 `/n/topic/388420?sort=old` → `/topic/388420`。
  static String? canonicalTopicPath(String url) {
    final info = parseTopic(url);
    if (info == null) return null;
    final base = '/topic/${info.topicId}';
    return info.postNumber == null ? base : '$base/${info.postNumber}';
  }

  /// 解析仅含 slug 的话题链接（/t/some-slug），返回 slug 或 null
  ///
  /// 注意：此方法仅匹配没有数字 ID 的 slug 链接，
  /// 带 ID 的链接应使用 [parseTopic]。
  static String? parseTopicSlug(String url) {
    final segments = _pathSegments(url);
    final topicIndex = _lastIndexOfAny(segments, const {'t'});
    if (topicIndex < 0 || topicIndex + 1 >= segments.length) return null;

    final remaining = segments.sublist(topicIndex + 1);
    if (remaining.length != 1) return null;
    final slug = remaining.first;
    if (slug.isEmpty || int.tryParse(slug) != null || _hasExtension(slug)) {
      return null;
    }
    return slug;
  }

  /// 解析 Discourse 帖子短链接 `/p/<post_id>`。
  static PostShortLinkInfo? parsePostShortLink(String url) {
    final segments = _pathSegments(url);
    final postIndex = _lastIndexOfAny(segments, const {'p'});
    if (postIndex < 0 || postIndex + 1 >= segments.length) return null;

    final remaining = segments.sublist(postIndex + 1);
    if (remaining.length > 2) return null;
    final postId = int.tryParse(segments[postIndex + 1]);
    if (postId == null || postId <= 0) return null;
    if (remaining.length == 2 && int.tryParse(remaining[1]) == null) {
      return null;
    }
    return PostShortLinkInfo(postId: postId);
  }

  /// 解析用户链接，返回 [UserLinkInfo] 或 null
  static UserLinkInfo? parseUser(String url) {
    final match = _userRegex.firstMatch(url);
    if (match != null) {
      return UserLinkInfo(username: match.group(1)!);
    }
    return null;
  }

  /// 是否是用户链接（用于快速判断）
  static bool isUserLink(String url) {
    return _userRegex.hasMatch(url);
  }

  static int? _parsePostNumberFromFragment(String url) {
    final uri = UrlParseUtils.tryParseLenient(url);
    final fragment = uri?.fragment;
    if (fragment == null || fragment.isEmpty) {
      return null;
    }
    final match = _postFragmentRegex.firstMatch(fragment);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static TopicLinkInfo? _parseRegularTopic(
    List<String> segments,
    int topicIndex,
    String url,
  ) {
    final remaining = segments.sublist(topicIndex + 1);
    if (remaining.isEmpty) return null;

    final first = remaining[0];
    final directTopicId = int.tryParse(first);
    if (directTopicId != null) {
      if (remaining.length > 2) return null;
      final postSegment = remaining.length == 2 ? remaining[1] : null;
      final postNumber = _parsePostNumberSegment(postSegment);
      if (postSegment != null && postNumber == null && postSegment != 'last') {
        return null;
      }
      return TopicLinkInfo(
        topicId: directTopicId,
        postNumber: postNumber ?? _parsePostNumberFromFragment(url),
      );
    }

    if (remaining.length < 2) return null;
    final topicId = int.tryParse(remaining[1]);
    if (topicId == null) return null;

    if (remaining.length > 3) return null;
    final postSegment = remaining.length == 3 ? remaining[2] : null;
    final postNumber = _parsePostNumberSegment(postSegment);
    final isKnownTopicAction =
        postSegment == null ||
        postSegment == 'last' ||
        postSegment == 'summary' ||
        postSegment == 'print' ||
        postSegment == 'wordpress';
    if (postSegment != null && postNumber == null && !isKnownTopicAction) {
      return null;
    }

    return TopicLinkInfo(
      topicId: topicId,
      slug: _normalizeSlug(first),
      postNumber: postNumber ?? _parsePostNumberFromFragment(url),
    );
  }

  static TopicLinkInfo? _parseNestedTopic(
    List<String> segments,
    int topicIndex,
    String url,
  ) {
    final remaining = segments.sublist(topicIndex + 1);
    if (remaining.length < 2) return null;

    final slug = remaining[0];
    final topicId = int.tryParse(remaining[1]);
    if (topicId == null) return null;
    if (remaining.length > 4) return null;

    int? postNumber;
    if (remaining.length >= 3) {
      postNumber = _parsePostNumberSegment(remaining[2]);
      if (postNumber == null &&
          remaining.length >= 4 &&
          (remaining[2] == 'context' || remaining[2] == 'children')) {
        postNumber = _parsePostNumberSegment(remaining[3]);
      }
      final hasValidNestedTail =
          postNumber != null ||
          remaining[2] == 'last' ||
          (remaining.length == 4 &&
              (remaining[2] == 'context' || remaining[2] == 'children') &&
              _parsePostNumberSegment(remaining[3]) != null);
      if (!hasValidNestedTail) return null;
    }

    return TopicLinkInfo(
      topicId: topicId,
      slug: _normalizeSlug(slug),
      postNumber: postNumber ?? _parsePostNumberFromFragment(url),
      isNestedRoute: true,
    );
  }

  static TopicLinkInfo? _parseCanonicalTopic(
    List<String> segments,
    int topicIndex,
    String url,
  ) {
    final remaining = segments.sublist(topicIndex + 1);
    if (remaining.isEmpty) return null;

    final topicId = int.tryParse(remaining[0]);
    if (topicId == null || topicId <= 0) return null;
    if (remaining.length > 2) return null;

    final postSegment = remaining.length == 2 ? remaining[1] : null;
    final postNumber = _parsePostNumberSegment(postSegment);
    if (postSegment != null && postNumber == null && postSegment != 'last') {
      return null;
    }

    return TopicLinkInfo(
      topicId: topicId,
      postNumber: postNumber ?? _parsePostNumberFromFragment(url),
    );
  }

  static List<String> _pathSegments(String url) {
    final uri = UrlParseUtils.tryParseLenient(url);
    if (uri != null) {
      return uri.pathSegments
          .map(Uri.decodeComponent)
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
    }

    return url
        .split('?')
        .first
        .split('#')
        .first
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  static int _lastIndexOfAny(List<String> segments, Set<String> markers) {
    for (var i = segments.length - 1; i >= 0; i--) {
      if (markers.contains(segments[i].toLowerCase())) return i;
    }
    return -1;
  }

  static int? _parsePostNumberSegment(String? segment) {
    if (segment == null || segment == 'last') return null;
    if (_hasExtension(segment)) return null;
    final postNumber = int.tryParse(segment);
    return postNumber != null && postNumber > 0 ? postNumber : null;
  }

  static String? _normalizeSlug(String slug) {
    return slug == 'topic' ? null : slug;
  }

  static bool _hasExtension(String segment) => segment.contains('.');
}
