import '../utils/url_helper.dart';

/// 统一头像 URL 选择策略。
///
/// 默认优先动态图；当用户开启“静态头像优先”后，统一回退到静态模板地址。
class AvatarUrlPolicy {
  AvatarUrlPolicy._();

  static final RegExp _discourseAnimatedAvatarPattern = RegExp(
    r'(/user_avatar/(?:[^/?#]+/){3})(\d+)_\d+\.(?:gif|webp|apng|avif)(?=([?#]|$))',
    caseSensitive: false,
  );
  static final RegExp _animatedImageExtensionPattern = RegExp(
    r'\.(gif|webp|apng|avif)$',
    caseSensitive: false,
  );

  static bool _preferStaticAvatars = false;

  static bool get preferStaticAvatars => _preferStaticAvatars;

  static void setPreferStaticAvatars(bool value) {
    _preferStaticAvatars = value;
  }

  static String resolve({
    required String? avatarTemplate,
    String? animatedAvatar,
    required int size,
  }) {
    final staticUrl = resolveTemplate(avatarTemplate, size: size);
    final animatedUrl = resolveAnimated(animatedAvatar);
    if (_preferStaticAvatars) {
      return staticUrl.isNotEmpty
          ? staticUrl
          : resolveImageUrl(animatedUrl, preferStaticAvatars: true);
    }
    return animatedUrl.isNotEmpty ? animatedUrl : staticUrl;
  }

  static String resolveTemplate(String? avatarTemplate, {required int size}) {
    if (avatarTemplate == null || avatarTemplate.isEmpty) return '';
    final template = avatarTemplate.replaceAll('{size}', size.toString());
    return UrlHelper.resolveUrlWithCdn(template);
  }

  static String resolveAnimated(String? animatedAvatar) {
    if (animatedAvatar == null || animatedAvatar.isEmpty) return '';
    return UrlHelper.resolveUrlWithCdn(animatedAvatar);
  }

  /// 解析直接传入的头像图片 URL。
  ///
  /// 某些头像来自 HTML/onebox 的 `<img class="avatar">`，没有模型层的
  /// `avatar_template` 可用。开启静态头像时，这里会尽量把 Discourse 动态
  /// 头像 URL 规范化为同一头像 ID 的 PNG 静态图；无法推导的 URL 保持原样，
  /// 由头像组件降级为首帧静态渲染。
  static String resolveImageUrl(String? imageUrl, {bool? preferStaticAvatars}) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    final shouldPreferStatic = preferStaticAvatars ?? _preferStaticAvatars;
    final normalized = shouldPreferStatic
        ? staticizeAnimatedAvatarUrl(imageUrl)
        : imageUrl;
    return UrlHelper.resolveUrlWithCdn(normalized);
  }

  static String staticizeAnimatedAvatarUrl(String url) {
    if (url.isEmpty) return url;
    return url.replaceFirstMapped(_discourseAnimatedAvatarPattern, (match) {
      final prefix = match.group(1)!;
      final avatarId = match.group(2)!;
      return '$prefix$avatarId.png';
    });
  }

  static bool isAnimatedImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final path = _pathWithoutQuery(url).toLowerCase();
    return _animatedImageExtensionPattern.hasMatch(path);
  }

  static bool shouldRenderAsStaticImage(
    String? url, {
    bool? preferStaticAvatars,
  }) {
    final shouldPreferStatic = preferStaticAvatars ?? _preferStaticAvatars;
    return shouldPreferStatic && isAnimatedImageUrl(url);
  }

  static String _pathWithoutQuery(String url) {
    final queryIndex = url.indexOf('?');
    final fragmentIndex = url.indexOf('#');
    final end = [
      if (queryIndex >= 0) queryIndex,
      if (fragmentIndex >= 0) fragmentIndex,
    ].fold<int>(url.length, (min, index) => index < min ? index : min);
    return url.substring(0, end);
  }
}
