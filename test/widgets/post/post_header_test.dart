import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_header.dart';

void main() {
  testWidgets('uses display name by default and keeps username secondary', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(useUsernameAsPrimaryLabel: false));

    expect(find.text('Custom Name'), findsOneWidget);
    expect(find.text('@account_name'), findsOneWidget);
  });

  testWidgets('can use username as the primary author label', (tester) async {
    await tester.pumpWidget(_buildApp(useUsernameAsPrimaryLabel: true));

    expect(find.text('Custom Name'), findsNothing);
    expect(find.text('@account_name'), findsOneWidget);
  });

  testWidgets('shows trust level badge below primary username', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        useUsernameAsPrimaryLabel: true,
        post: _post(userTitle: '活跃用户'),
      ),
    );

    expect(find.text('@account_name'), findsOneWidget);
    expect(find.text('LV3'), findsOneWidget);
    expect(find.text('活跃用户'), findsNothing);
  });

  test('resolves trust level from API field before title fallback', () {
    expect(resolvePostTrustLevel(trustLevel: 4, userTitle: '活跃用户'), 4);
    expect(resolvePostTrustLevel(userTitle: '活跃用户'), 3);
    expect(resolvePostTrustLevel(userTitle: 'LV2'), 2);
    expect(resolvePostTrustLevel(userTitle: '自定义头衔'), isNull);
    expect(postTrustLevelLabel(3), 'LV3');
  });
}

Widget _buildApp({required bool useUsernameAsPrimaryLabel, Post? post}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: PostHeader(
          post: post ?? _post(),
          topicId: 42,
          isTopicOwner: true,
          isOwnPost: false,
          isWhisper: false,
          useUsernameAsPrimaryLabel: useUsernameAsPrimaryLabel,
          cachedAvatarWidget: const SizedBox(width: 40, height: 40),
          isLoadingReplyHistoryNotifier: null,
          onToggleReplyHistory: null,
          buildCompactBadge: (context, text, backgroundColor, textColor) {
            return Text(text);
          },
          timeAndFloorWidget: const Text('#1'),
        ),
      ),
    ),
  );
}

Post _post({String? userTitle, int? trustLevel}) {
  final createdAt = DateTime.utc(2026, 7, 7, 12);
  return Post(
    id: 101,
    topicId: 42,
    name: 'Custom Name',
    username: 'account_name',
    avatarTemplate: '',
    cooked: '<p>content</p>',
    postNumber: 1,
    postType: 1,
    updatedAt: createdAt,
    createdAt: createdAt,
    likeCount: 0,
    replyCount: 0,
    userTitle: userTitle,
    trustLevel: trustLevel,
  );
}
