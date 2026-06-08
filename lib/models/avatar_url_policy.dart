import 'package:flutter/foundation.dart';

import '../utils/url_helper.dart';

/// 统一头像 URL 选择策略。
///
/// 默认优先动态图；当用户开启“静态头像优先”后，统一回退到静态模板地址。
class AvatarUrlPolicy {
  AvatarUrlPolicy._();

  static bool _preferStaticAvatars = false;
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  static bool get preferStaticAvatars => _preferStaticAvatars;
  static ValueListenable<int> get revisionListenable => _revision;

  static void setPreferStaticAvatars(bool value) {
    if (_preferStaticAvatars == value) return;
    _preferStaticAvatars = value;
    _revision.value++;
  }

  static String resolve({
    required String? avatarTemplate,
    String? animatedAvatar,
    required int size,
  }) {
    final staticUrl = resolveTemplate(avatarTemplate, size: size);
    if (_preferStaticAvatars) {
      final staticFromAnimated = resolveDirectAvatarUrl(
        animatedAvatar,
        size: size,
      );
      return staticUrl.isNotEmpty ? staticUrl : staticFromAnimated;
    }
    final animatedUrl = resolveAnimated(animatedAvatar);
    return animatedUrl.isNotEmpty ? animatedUrl : staticUrl;
  }

  static String resolveTemplate(String? avatarTemplate, {required int size}) {
    if (avatarTemplate == null || avatarTemplate.isEmpty) return '';
    final template = avatarTemplate.replaceAll('{size}', size.toString());
    return resolveDirectAvatarUrl(template, size: size);
  }

  static String resolveAnimated(String? animatedAvatar) {
    if (animatedAvatar == null || animatedAvatar.isEmpty) return '';
    return UrlHelper.resolveUrlWithCdn(animatedAvatar);
  }

  static String resolveDirectAvatarUrl(String? avatarUrl, {int? size}) {
    if (avatarUrl == null || avatarUrl.isEmpty) return '';

    final staticCandidate = _preferStaticAvatars
        ? _toStaticAvatarCandidate(avatarUrl, size: size)
        : avatarUrl;
    final resolved = UrlHelper.resolveUrlWithCdn(staticCandidate);

    if (_preferStaticAvatars && _isAnimatedAvatarUrl(resolved)) {
      return '';
    }
    return resolved;
  }

  static String _toStaticAvatarCandidate(String avatarUrl, {int? size}) {
    var result = avatarUrl;
    if (size != null) {
      result = result.replaceAll('{size}', size.toString());
    }

    final uri = Uri.tryParse(result);
    final path = uri?.path ?? result.split('?').first;
    if (!path.toLowerCase().startsWith('/user_avatar/') &&
        !path.toLowerCase().contains('/user_avatar/')) {
      return result;
    }

    return result.replaceFirst(
      RegExp(r'\.(?:gif|webp|avif)(?=($|\?))', caseSensitive: false),
      '.png',
    );
  }

  static bool _isAnimatedAvatarUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    final isAvatarPath =
        path.startsWith('/user_avatar/') || path.contains('/user_avatar/');
    if (!isAvatarPath) return false;

    return path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.avif');
  }
}
