import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_bubble.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_content.dart';

void main() {
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

    await tester.tap(find.byType(CircleAvatar));
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

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pump();

    expect(tappedUser?.username, 'bob');
    expect(groupTapCount, 0);
  });
}

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
