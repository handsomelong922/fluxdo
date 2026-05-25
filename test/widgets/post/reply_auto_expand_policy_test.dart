import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/post/reply_auto_expand_policy.dart';

void main() {
  group('reply auto expand policy', () {
    test('auto expands only small direct reply groups', () {
      expect(shouldAutoExpandReplyCount(0), isFalse);
      expect(shouldAutoExpandReplyCount(1), isTrue);
      expect(shouldAutoExpandReplyCount(autoExpandReplyThreshold), isTrue);
      expect(shouldAutoExpandReplyCount(autoExpandReplyThreshold + 1), isFalse);
    });
  });
}
