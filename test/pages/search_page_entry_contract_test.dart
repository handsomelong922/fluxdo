import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('搜索页入场只读本地状态且立即请求输入焦点', () {
    final source = File('lib/pages/search_page.dart').readAsStringSync();

    expect(source, isNot(contains('.getRecentSearches()')));
    expect(source, isNot(contains('.clearRecentSearches()')));
    expect(source, isNot(contains('isAiSemanticSearchEnabled()')));
    expect(source, isNot(contains('_isLoadingRecentSearches')));
    expect(source, contains('siteSettingsSync'));
    expect(source, contains('_focusNode.requestFocus()'));
  });
}
