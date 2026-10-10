import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 静态装配契约：覆盖加载前后共用的普通顶栏，不能替代真机转场验证。
String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  if (startIndex < 0) throw StateError('找不到起始标记：$start');
  final endIndex = source.indexOf(end, startIndex);
  if (endIndex <= startIndex) throw StateError('找不到结束标记：$end');
  return source.substring(startIndex, endIndex);
}

void main() {
  final source = File(
    'lib/pages/topic_detail_page/topic_detail_page.dart',
  ).readAsStringSync();
  final appBarBuilder = _section(
    source,
    '  PreferredSizeWidget _buildAppBar({',
    '  bool _canEditTopic(',
  );
  final normalAppBar = appBarBuilder.substring(
    appBarBuilder.lastIndexOf('return AppBar('),
  );

  test('普通话题顶栏加载前后都不装配重复标题', () {
    expect(normalAppBar, isNot(matches(RegExp(r'\btitle\s*:'))));
    expect(appBarBuilder, isNot(contains('_buildAppBarTitle')));
  });

  test('普通话题顶栏不绘制背景、滚动着色和阴影', () {
    expect(normalAppBar, contains('backgroundColor: Colors.transparent'));
    expect(normalAppBar, contains('surfaceTintColor: Colors.transparent'));
    expect(normalAppBar, contains('shadowColor: Colors.transparent'));
    expect(normalAppBar, contains('elevation: 0'));
    expect(normalAppBar, contains('scrolledUnderElevation: 0'));
  });

  test('透明顶栏按主题指定状态栏图标亮暗', () {
    expect(
      normalAppBar,
      contains('systemOverlayStyle: theme.brightness == Brightness.dark'),
    );
    expect(normalAppBar, contains('? SystemUiOverlayStyle.light'));
    expect(normalAppBar, contains(': SystemUiOverlayStyle.dark'));
  });

  test('普通顶栏仍保留返回、搜索和更多入口', () {
    expect(
      normalAppBar,
      contains('automaticallyImplyLeading: !widget.embeddedMode'),
    );
    expect(normalAppBar, contains('BackButton(onPressed: widget.onEmbeddedBack)'));
    expect(normalAppBar, contains('actions: _buildAppBarActions('));
    final actions = _section(
      source,
      '  List<Widget> _buildAppBarActions({',
      '  Widget _buildMoreMenuAction({',
    );
    expect(actions, contains('_buildSearchAction()'));
    expect(actions, contains('_buildMoreMenuAction('));
  });

  test('搜索模式保留输入框和退出按钮', () {
    final searchAppBar = appBarBuilder.substring(
      0,
      appBarBuilder.indexOf('// 正常模式下的 AppBar'),
    );
    expect(searchAppBar, contains('title: TextField('));
    expect(searchAppBar, contains('backgroundColor: theme.colorScheme.surface'));
    expect(searchAppBar, contains('onPressed: _exitSearchMode'));
  });

  test('透明顶栏仍占据布局高度，不让正文延伸到按钮后面', () {
    final scaffold = _section(
      source,
      '    final topicScaffold = Scaffold(',
      '    // 无 AI 模型或非滑动入口模式',
    );
    expect(scaffold, contains('appBar: PreferredSize('));
    expect(scaffold, contains('Size.fromHeight(kToolbarHeight)'));
    expect(scaffold, isNot(contains('extendBodyBehindAppBar: true')));
  });

  test('正文标题和手机书签工作区的独立标题仍保留', () {
    final nested = File(
      'lib/pages/topic_detail_page/widgets/nested_post_list.dart',
    ).readAsStringSync();
    expect(nested, contains('showTitle: !widget.hideHeaderTitle'));
    final workspace = _section(
      source,
      '  PreferredSizeWidget _buildEmbeddedMobileWorkspaceAppBar({',
      '  Widget _buildEmbeddedMobileWorkspaceTitle(',
    );
    expect(
      workspace,
      contains('title: _buildEmbeddedMobileWorkspaceTitle(theme, detail)'),
    );
  });
}
