import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/user_profile_page.dart';

void main() {
  group('userProfileInitialTabIndex', () {
    test('默认选择话题 filter', () {
      expect(
        userProfileInitialTabIndex(const [
          'summary',
          '4,5',
          '4',
          '5',
          '1',
          'reactions',
        ]),
        2,
      );
    });

    test('标签定义缺少话题时安全回退到首项', () {
      expect(userProfileInitialTabIndex(const ['summary', '4,5']), 0);
    });
  });
}
