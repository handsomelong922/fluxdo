import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/modules/ldc_reward/widgets/ldc_reward_config_tile.dart';

void main() {
  group('sanitizeLdcCredential', () {
    test('移除空白与零宽字符', () {
      const input = '  cli\u200Bent\n\t-\u200C1\u200D23\uFEFF  ';

      expect(sanitizeLdcCredential(input), 'client-123');
    });

    test('保留正常凭证字符', () {
      expect(sanitizeLdcCredential('abc_DEF-123'), 'abc_DEF-123');
    });
  });
}
