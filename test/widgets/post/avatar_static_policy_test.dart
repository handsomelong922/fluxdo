import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/flair_badge.dart';
import 'package:fluxdo/widgets/nested/nested_post_gutter.dart';

void main() {
  test('nested mobile avatars use a static template', () {
    expect(
      resolveNestedPostAvatarUrl(
        avatarTemplate: '/user_avatar/linux.do/alice/{size}/1.gif',
        platform: TargetPlatform.android,
      ),
      'https://linux.do/user_avatar/linux.do/alice/36/1.png',
    );
  });

  test('nested desktop avatars keep existing template behavior', () {
    expect(
      resolveNestedPostAvatarUrl(
        avatarTemplate: '/user_avatar/linux.do/alice/{size}/1.gif',
        platform: TargetPlatform.windows,
      ),
      'https://linux.do/user_avatar/linux.do/alice/36/1.gif',
    );
  });

  test('mobile flair hides an animated URL without a static candidate', () {
    expect(
      resolveFlairBadgeImageUrl(
        url: 'https://linux.do/flair/animated.gif',
        platform: TargetPlatform.android,
        size: 20,
      ),
      isEmpty,
    );
  });

  test('desktop flair keeps existing image behavior', () {
    expect(
      resolveFlairBadgeImageUrl(
        url: 'https://linux.do/flair/animated.gif',
        platform: TargetPlatform.windows,
        size: 20,
      ),
      'https://linux.do/flair/animated.gif',
    );
  });
}
