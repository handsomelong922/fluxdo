import 'package:flutter/material.dart';
import '../../models/avatar_url_policy.dart';
import '../../pages/user_profile_page.dart';
import '../common/smart_avatar.dart';

/// 嵌套帖子左侧头像（可点击跳转用户主页）
class NestedPostAvatar extends StatelessWidget {
  final String avatarTemplate;
  final String username;
  static const double size = 24.0;

  const NestedPostAvatar({
    super.key,
    required this.avatarTemplate,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfilePage(username: username)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: AvatarUrlPolicy.revisionListenable,
        builder: (context, _, _) {
          final avatarUrl = AvatarUrlPolicy.resolveTemplate(
            avatarTemplate,
            size: 48,
          );
          return SmartAvatar(
            imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
            radius: size / 2,
            fallbackText: username,
          );
        },
      ),
    );
  }
}
