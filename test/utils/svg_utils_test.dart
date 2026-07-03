import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/svg_utils.dart';

void main() {
  test('looksLikeSvgUrl only matches likely svg sources', () {
    expect(SvgUtils.looksLikeSvgUrl('https://cdn.example.com/avatar.png'), isFalse);
    expect(SvgUtils.looksLikeSvgUrl('https://cdn.example.com/icon.svg'), isTrue);
    expect(SvgUtils.looksLikeSvgUrl('data:image/svg+xml;base64,AAAA'), isTrue);
    expect(
      SvgUtils.looksLikeSvgUrl('https://cdn.example.com/avatar?format=svg'),
      isTrue,
    );
  });
}
