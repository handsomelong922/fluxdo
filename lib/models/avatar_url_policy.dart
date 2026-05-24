import '../utils/url_helper.dart';

/// 统一头像 URL 选择策略。
///
/// 默认优先动态图；当用户开启“静态头像优先”后，统一回退到静态模板地址。
class AvatarUrlPolicy {
  AvatarUrlPolicy._();

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
      return staticUrl.isNotEmpty ? staticUrl : animatedUrl;
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
}
