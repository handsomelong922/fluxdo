import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/avatar_url_policy.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/common/smart_avatar.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_bubble.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_content.dart';

void main() {
  tearDown(() {
    AvatarUrlPolicy.setPreferStaticAvatars(false);
  });

  testWidgets('点击单个 Boost 头像只触发头像回调', (tester) async {
    BoostUser? tappedUser;
    var bubbleTapCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        BoostBubble(
          boost: const Boost(
            id: 1,
            cooked: '<p>hi</p>',
            user: BoostUser(id: 2, username: 'bob', avatarTemplate: ''),
          ),
          onTap: () => bubbleTapCount++,
          onAvatarTap: (user) => tappedUser = user,
        ),
      ),
    );

    await tester.tap(find.byType(SmartAvatar));
    await tester.pump();

    expect(tappedUser?.username, 'bob');
    expect(bubbleTapCount, 0);
  });

  testWidgets('长按单个 Boost 触发长按回调', (tester) async {
    var longPressCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        BoostBubble(
          key: const ValueKey('boost-bubble'),
          boost: const Boost(
            id: 1,
            cooked: '<p>hi</p>',
            user: BoostUser(id: 2, username: 'bob', avatarTemplate: ''),
          ),
          onLongPress: () => longPressCount++,
        ),
      ),
    );

    await tester.longPress(find.byKey(const ValueKey('boost-bubble')));
    await tester.pump();

    expect(longPressCount, 1);
  });

  testWidgets('点击分组 Boost 头像触发对应用户回调', (tester) async {
    BoostUser? tappedUser;
    var groupTapCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        BoostBubble.group(
          group: const BoostGroup(
            displayText: 'hi',
            groupingKey: 'hi',
            boosts: [
              Boost(
                id: 1,
                cooked: '<p>hi</p>',
                user: BoostUser(id: 2, username: 'bob', avatarTemplate: ''),
              ),
              Boost(
                id: 2,
                cooked: '<p>hi</p>',
                user: BoostUser(id: 3, username: 'alice', avatarTemplate: ''),
              ),
            ],
          ),
          onTap: () => groupTapCount++,
          onAvatarTap: (user) => tappedUser = user,
        ),
      ),
    );

    await tester.tap(find.byType(SmartAvatar).first);
    await tester.pump();

    expect(tappedUser?.username, 'bob');
    expect(groupTapCount, 0);
  });

  testWidgets('单个 Boost 头像始终使用静态 URL 且只有 SmartAvatar 自身监听', (tester) async {
    AvatarUrlPolicy.setPreferStaticAvatars(false);

    await tester.pumpWidget(
      _buildTestApp(
        const BoostBubble(
          boost: Boost(
            id: 1,
            cooked: '<p>hi</p>',
            user: BoostUser(
              id: 2,
              username: 'bob',
              avatarTemplate: '/user_avatar/linux.do/bob/{size}/1.gif',
            ),
          ),
        ),
      ),
    );

    final avatar = tester.widget<SmartAvatar>(find.byType(SmartAvatar));
    expect(avatar.imageUrl, contains('/bob/48/1.png'));
    expect(
      find.byWidgetPredicate((widget) => widget is ValueListenableBuilder<int>),
      findsOneWidget,
    );
  });

  testWidgets('分组 Boost 头像全部使用静态 URL 且不重复监听头像策略', (tester) async {
    AvatarUrlPolicy.setPreferStaticAvatars(false);

    await tester.pumpWidget(
      _buildTestApp(
        const BoostBubble.group(
          group: BoostGroup(
            displayText: 'hi',
            groupingKey: 'hi',
            boosts: [
              Boost(
                id: 1,
                cooked: '<p>hi</p>',
                user: BoostUser(
                  id: 2,
                  username: 'bob',
                  avatarTemplate: '/user_avatar/linux.do/bob/{size}/1.webp',
                ),
              ),
              Boost(
                id: 2,
                cooked: '<p>hi</p>',
                user: BoostUser(
                  id: 3,
                  username: 'alice',
                  avatarTemplate: '/user_avatar/linux.do/alice/{size}/2.avif',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final avatars = tester
        .widgetList<SmartAvatar>(find.byType(SmartAvatar))
        .toList(growable: false);
    expect(avatars, hasLength(2));
    expect(avatars[0].imageUrl, contains('/bob/48/1.png'));
    expect(avatars[1].imageUrl, contains('/alice/48/2.png'));
    expect(
      find.byWidgetPredicate((widget) => widget is ValueListenableBuilder<int>),
      findsNWidgets(2),
    );
  });
}

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
