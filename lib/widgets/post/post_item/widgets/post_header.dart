import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../../l10n/s.dart';
import '../../../../constants.dart';
import '../../../../models/avatar_url_policy.dart';
import '../../../../models/topic.dart';
import '../../../../pages/user_profile_page.dart';
import '../../../../services/discourse_cache_manager.dart';
import '../../../../services/emoji_handler.dart';
import '../../../common/flair_badge.dart';
import '../../../common/smart_avatar.dart';
import '../../../common/avatar_glow.dart';
import '../../whisper_indicator.dart';
import 'post_granted_badge.dart';

/// 获取 emoji 图片 URL（未加载完成时返回空字符串，由 errorBuilder 处理）
String _getEmojiUrl(String emojiName) {
  return EmojiHandler().getEmojiUrl(emojiName);
}

@visibleForTesting
int? resolvePostTrustLevel({int? trustLevel, String? userTitle}) {
  if (trustLevel != null) return trustLevel;

  final normalized = (userTitle ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    '',
  );
  if (normalized.isEmpty) return null;

  final levelMatch = RegExp(r'^(?:l|lv)(\d+)$').firstMatch(normalized);
  if (levelMatch != null) {
    return int.tryParse(levelMatch.group(1)!);
  }

  return switch (normalized) {
    '新用户' || 'newuser' => 0,
    '基本用户' || 'basicuser' => 1,
    '成员' || 'member' => 2,
    '活跃用户' || 'regular' => 3,
    '领导者' || '领袖' || 'leader' => 4,
    _ => null,
  };
}

@visibleForTesting
String postTrustLevelLabel(int level) => 'LV$level';

/// 帖子头像组件（独立widget避免不必要的重建）
class PostAvatar extends StatefulWidget {
  final Post post;
  final ThemeData theme;
  final double radius;

  const PostAvatar({
    super.key,
    required this.post,
    required this.theme,
    this.radius = 20,
  });

  @override
  State<PostAvatar> createState() => _PostAvatarState();
}

class _PostAvatarState extends State<PostAvatar> {
  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.post.getAvatarUrl(
      size: (widget.radius * 2).round(),
    );
    final glowColor = AppConstants.siteCustomization.matchAvatarGlow(
      widget.post,
    );

    Widget avatar = AvatarWithFlair(
      flairSize: widget.radius * 0.85,
      flairRight: -4,
      flairBottom: -2,
      flairUrl: widget.post.flairUrl,
      flairName: widget.post.flairName,
      flairBgColor: widget.post.flairBgColor,
      flairColor: widget.post.flairColor,
      avatar: SmartAvatar(
        imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
        radius: widget.radius,
        fallbackText: widget.post.username,
        border: Border.all(
          color: widget.theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
    );

    final isMobilePlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (glowColor != null &&
        !isMobilePlatform &&
        !AvatarUrlPolicy.preferStaticAvatars) {
      avatar = AvatarGlow(glowColor: glowColor, child: avatar);
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfilePage(username: widget.post.username),
        ),
      ),
      child: avatar,
    );
  }
}

/// 帖子头部组件（头像、用户名、时间、徽章）
class PostHeader extends StatelessWidget {
  final Post post;
  final int topicId;
  final bool isTopicOwner;
  final bool isOwnPost;
  final bool isWhisper;
  final bool useUsernameAsPrimaryLabel;
  final Widget cachedAvatarWidget;
  final ValueNotifier<bool>? isLoadingReplyHistoryNotifier;
  final VoidCallback? onToggleReplyHistory;

  /// 自定义回复指示点击回调（用于弹框内滚动跳转，不加载回复历史）
  final VoidCallback? onReplyIndicatorTap;

  /// 隐藏回复指示器
  final bool hideReplyIndicator;
  final Widget Function(
    BuildContext context,
    String text,
    Color backgroundColor,
    Color textColor,
  )
  buildCompactBadge;
  final Widget timeAndFloorWidget;

  const PostHeader({
    super.key,
    required this.post,
    required this.topicId,
    required this.isTopicOwner,
    required this.isOwnPost,
    required this.isWhisper,
    this.useUsernameAsPrimaryLabel = false,
    required this.cachedAvatarWidget,
    required this.isLoadingReplyHistoryNotifier,
    required this.onToggleReplyHistory,
    this.onReplyIndicatorTap,
    this.hideReplyIndicator = false,
    required this.buildCompactBadge,
    required this.timeAndFloorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryAuthorLabel = useUsernameAsPrimaryLabel
        ? '@${post.username}'
        : (post.name != null && post.name!.isNotEmpty)
        ? post.name!
        : post.username;
    final trustLevel = resolvePostTrustLevel(
      trustLevel: post.trustLevel,
      userTitle: post.userTitle,
    );
    final hasTrustLevel = trustLevel != null;
    final hasFallbackUserTitle =
        trustLevel == null &&
        post.userTitle != null &&
        post.userTitle!.isNotEmpty;
    final hasGrantedBadges =
        post.badgesGranted != null && post.badgesGranted!.isNotEmpty;
    final showSecondaryAuthorRow =
        !useUsernameAsPrimaryLabel ||
        hasTrustLevel ||
        hasFallbackUserTitle ||
        hasGrantedBadges;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        cachedAvatarWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      primaryAuthorLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: (post.moderator || post.admin)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // 版主盾牌图标（版主或分类群组版主）
                  if (post.moderator || post.groupModerator) ...[
                    const SizedBox(width: 4),
                    FaIcon(
                      FontAwesomeIcons.shieldHalved,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                  // 用户状态 emoji
                  if (post.userStatus?.emoji != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: post.userStatus!.description ?? '',
                      child: Image(
                        image: emojiImageProvider(
                          _getEmojiUrl(post.userStatus!.emoji!),
                        ),
                        width: 16,
                        height: 16,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  if (isTopicOwner && post.postNumber > 1) ...[
                    const SizedBox(width: 4),
                    buildCompactBadge(
                      context,
                      context.l10n.post_opBadge,
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.onPrimaryContainer,
                    ),
                  ],
                  if (isOwnPost) ...[
                    const SizedBox(width: 4),
                    buildCompactBadge(
                      context,
                      context.l10n.post_meBadge,
                      theme.colorScheme.tertiaryContainer,
                      theme.colorScheme.onTertiaryContainer,
                    ),
                  ],
                  if (isWhisper) ...[
                    const SizedBox(width: 8),
                    const WhisperIndicator(),
                  ],
                ],
              ),
              // @username + 用户头衔 + 帖子头部徽章
              if (showSecondaryAuthorRow)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      if (!useUsernameAsPrimaryLabel)
                        Text(
                          '@${post.username}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      if (!useUsernameAsPrimaryLabel &&
                          (hasTrustLevel ||
                              hasFallbackUserTitle ||
                              hasGrantedBadges))
                        const SizedBox(width: 6),
                      if (hasTrustLevel)
                        _buildTrustLevelBadge(context, theme, trustLevel),
                      if (hasTrustLevel &&
                          (hasFallbackUserTitle || hasGrantedBadges))
                        const SizedBox(width: 4),
                      if (hasFallbackUserTitle)
                        Flexible(
                          child: () {
                            final titleBuilder = AppConstants.siteCustomization
                                .matchTitleStyle(post);
                            return titleBuilder != null
                                ? titleBuilder(post.userTitle!, 11)
                                : Text(
                                    post.userTitle!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.8),
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  );
                          }(),
                        ),
                      // 帖子头部徽章
                      if (hasGrantedBadges) ...[
                        if (!hasTrustLevel &&
                            !hasFallbackUserTitle &&
                            !useUsernameAsPrimaryLabel)
                          const SizedBox(width: 4)
                        else if (hasTrustLevel || hasFallbackUserTitle)
                          const SizedBox(width: 4),
                        ...post.badgesGranted!.map(
                          (badge) => PostGrantedBadgeIcon(badge: badge),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 右侧：回复指示 + 时间 + 楼层号
        _buildRightSection(context, theme),
      ],
    );
  }

  Widget _buildTrustLevelBadge(
    BuildContext context,
    ThemeData theme,
    int level,
  ) {
    final colors = _trustLevelColors(theme, level);
    return Semantics(
      label: 'Trust level ${postTrustLevelLabel(level)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.foreground.withValues(alpha: 0.18)),
        ),
        child: Text(
          postTrustLevelLabel(level),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.foreground,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  ({Color background, Color foreground}) _trustLevelColors(
    ThemeData theme,
    int level,
  ) {
    return switch (level) {
      0 => (
        background: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        foreground: theme.colorScheme.onSurfaceVariant,
      ),
      1 => (
        background: Colors.teal.withValues(alpha: 0.12),
        foreground: Colors.teal.shade700,
      ),
      2 => (
        background: Colors.blue.withValues(alpha: 0.12),
        foreground: Colors.blue.shade700,
      ),
      3 => (
        background: Colors.purple.withValues(alpha: 0.13),
        foreground: Colors.purple.shade700,
      ),
      4 => (
        background: Colors.amber.withValues(alpha: 0.20),
        foreground: Colors.orange.shade800,
      ),
      _ => (
        background: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        foreground: theme.colorScheme.primary,
      ),
    };
  }

  Widget _buildRightSection(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (post.replyToUser != null && !hideReplyIndicator) ...[
          if (onToggleReplyHistory != null)
            ValueListenableBuilder<bool>(
              valueListenable: isLoadingReplyHistoryNotifier!,
              builder: (context, isLoading, _) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isLoading ? null : onToggleReplyHistory,
                  child: _buildReplyIndicator(theme, isLoading: isLoading),
                );
              },
            )
          else if (onReplyIndicatorTap != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReplyIndicatorTap,
              child: _buildReplyIndicator(theme),
            )
          else
            _buildReplyIndicator(theme, showUsername: true),
          const SizedBox(width: 12),
        ],
        timeAndFloorWidget,
      ],
    );
  }

  Widget _buildReplyIndicator(
    ThemeData theme, {
    bool isLoading = false,
    bool showUsername = false,
  }) {
    final isMobilePlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final replyToUser = post.replyToUser!;
    final displayName =
        (replyToUser.name != null && replyToUser.name!.isNotEmpty)
        ? replyToUser.name!
        : replyToUser.username;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            Icon(Icons.more_horiz, size: 14, color: theme.colorScheme.primary)
          else
            Icon(Icons.reply, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          ValueListenableBuilder<int>(
            valueListenable: AvatarUrlPolicy.revisionListenable,
            builder: (context, _, _) {
              final templateAvatarUrl = AvatarUrlPolicy.resolveTemplate(
                replyToUser.avatarTemplate,
                size: 40,
              );
              final avatarUrl =
                  isMobilePlatform && !AvatarUrlPolicy.preferStaticAvatars
                  ? AvatarUrlPolicy.resolveStaticAvatarUrl(
                      templateAvatarUrl,
                      size: 40,
                    )
                  : templateAvatarUrl;
              return CircleAvatar(
                radius: 10,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: avatarUrl.isNotEmpty
                    ? discourseImageProvider(
                        avatarUrl,
                        maxWidth: 40,
                        maxHeight: 40,
                      )
                    : null,
                child: avatarUrl.isEmpty && replyToUser.username.isNotEmpty
                    ? Text(
                        replyToUser.username[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              );
            },
          ),
          if (showUsername) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                displayName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
