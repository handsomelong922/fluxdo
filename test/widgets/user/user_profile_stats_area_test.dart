import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/user/user_profile_stats_area.dart';

void main() {
  const primaryStats = <UserProfileStatData>[
    UserProfileStatData(value: '12', label: '关注', rawValue: 12),
    UserProfileStatData(value: '34', label: '粉丝', rawValue: 34),
  ];
  const secondaryStats = <UserProfileStatData>[
    UserProfileStatData(value: '56', label: '获赞', rawValue: 56),
    UserProfileStatData(value: '78', label: '访问', rawValue: 78),
    UserProfileStatData(value: '9', label: '话题', rawValue: 9),
    UserProfileStatData(value: '10', label: '回复', rawValue: 10),
  ];

  testWidgets('summary 从加载到完成时统计区和后续内容位置保持不变', (tester) async {
    Future<double> pump({required bool loading}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserProfileStatsArea(
                      key: const Key('profile-stats-area'),
                      primaryStats: primaryStats,
                      secondaryStats: loading ? null : secondaryStats,
                      isSummaryLoading: loading,
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(
                      key: Key('recent-activity'),
                      width: 80,
                      height: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('profile-stats-area'))).height,
        UserProfileStatsArea.height,
      );
      return tester.getTopLeft(find.byKey(const Key('recent-activity'))).dy;
    }

    final loadingActivityTop = await pump(loading: true);
    expect(find.byKey(const Key('profile-stats-loading')), findsOneWidget);

    final loadedActivityTop = await pump(loading: false);
    expect(find.text('获赞'), findsOneWidget);
    expect(loadedActivityTop, loadingActivityTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏统计区保持单行并保留点击行为', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 180,
            child: UserProfileStatsArea(
              primaryStats: [
                UserProfileStatData(
                  value: '12.3k',
                  label: 'Following',
                  rawValue: 12345,
                  onTap: () => taps++,
                ),
                const UserProfileStatData(
                  value: '45.6k',
                  label: 'Followers',
                  rawValue: 45678,
                ),
              ],
              secondaryStats: const [
                UserProfileStatData(
                  value: '1.2m',
                  label: 'Likes',
                  rawValue: 1200000,
                ),
                UserProfileStatData(
                  value: '365',
                  label: 'Visits',
                  rawValue: 365,
                ),
                UserProfileStatData(
                  value: '999',
                  label: 'Topics',
                  rawValue: 999,
                ),
                UserProfileStatData(
                  value: '9.9k',
                  label: 'Replies',
                  rawValue: 9900,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Following'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(UserProfileStatsArea)).height,
      UserProfileStatsArea.height,
    );
    expect(tester.takeException(), isNull);
  });
}
