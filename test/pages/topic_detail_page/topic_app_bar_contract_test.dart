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
  final source = File('lib/pages/topic_detail_page/topic_detail_page.dart')
      .readAsStringSync();
  final appBarBuilder = _section(
    source,
    '  PreferredSizeWidget _buildAppBar({',
    '  bool _canEditTopic(',
  );
  final normalAppBar = appBarBuilder.substring(
    appBarBuilder.lastIndexOf('return TopicFloatingAppBar('),
  );
  final floatingAppBar = File(
    'lib/pages/topic_detail_page/widgets/topic_floating_app_bar.dart',
  ).readAsStringSync();

  test('普通话题顶栏加载前后都不装配重复标题', () {
    expect(normalAppBar, isNot(matches(RegExp(r'\btitle\s*:'))));
    expect(appBarBuilder, isNot(contains('_buildAppBarTitle')));
  });

  test('普通话题顶栏不绘制背景、滚动着色和阴影', () {
    expect(floatingAppBar, contains('backgroundColor: Colors.transparent'));
    expect(floatingAppBar, contains('surfaceTintColor: Colors.transparent'));
    expect(floatingAppBar, contains('shadowColor: Colors.transparent'));
    expect(floatingAppBar, contains('elevation: 0'));
    expect(floatingAppBar, contains('scrolledUnderElevation: 0'));
    expect(floatingAppBar, contains('forceMaterialTransparency: true'));
  });

  test('透明顶栏按主题指定状态栏图标亮暗', () {
    expect(normalAppBar, contains('brightness: theme.brightness'));
    expect(floatingAppBar, contains('statusBarIconBrightness: brightness'));
    expect(floatingAppBar, contains('statusBarColor: Colors.transparent'));
    expect(floatingAppBar, contains('systemStatusBarContrastEnforced: false'));
  });

  test('普通顶栏仍保留返回、搜索和更多入口', () {
    expect(
      normalAppBar,
      contains('automaticallyImplyLeading: !widget.embeddedMode'),
    );
    expect(
      normalAppBar,
      contains('BackButton(onPressed: widget.onEmbeddedBack)'),
    );
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
    expect(
      searchAppBar,
      contains('backgroundColor: theme.colorScheme.surface'),
    );
    expect(searchAppBar, contains('onPressed: _exitSearchMode'));
  });

  test('搜索结果退出后等新视口布局再跳转，固定搜索栏不重复避让', () {
    final scrollController = _section(
      source,
      '      scrollController: AutoScrollController(',
      '      screenTrack: _screenTrack,',
    );
    expect(scrollController, contains('viewportBoundaryGetter:'));
    expect(scrollController, contains('ref.read(topicSearchProvider(widget.topicId)).isSearchMode'));
    final searchView = _section(
      source,
      '          TopicSearchView(',
      '        // TopicDetailOverlay (Bottom Bar)',
    );
    expect(searchView, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(searchView, contains('if (mounted) unawaited(_jumpToPostInTopic(postNumber))'));
  });

  test('普通顶栏不占据固定正文空间，搜索和书签工作区仍使用原顶栏布局', () {
    final scaffold = _section(
      source,
      '    final topicScaffold = Scaffold(',
      '    // 无 AI 模型或非滑动入口模式',
    );
    expect(scaffold, contains('appBar: PreferredSize('));
    expect(scaffold, contains('Size.fromHeight(kToolbarHeight)'));
    expect(scaffold, contains('extendBodyBehindAppBar: floatingAppBar'));
    expect(scaffold, contains('body: TopicContentBody('));
    expect(
      source,
      contains('!isSearchMode && !_usesEmbeddedMobileWorkspaceChrome'),
    );
    final bodyInsets = File(
      'lib/pages/topic_detail_page/widgets/topic_content_insets.dart',
    ).readAsStringSync();
    expect(bodyInsets, contains('floatingAppBar ? systemTopPadding : 0'));
    expect(bodyInsets, contains('top: floatingAppBar ? kToolbarHeight : 0'));
  });

  test('正文标题和手机书签工作区的独立标题仍保留', () {
    final nested = File(
      'lib/pages/topic_detail_page/widgets/nested_post_list.dart',
    ).readAsStringSync();
    expect(nested, contains('showTitle: !widget.hideHeaderTitle'));
    expect(
      nested,
      contains('topPadding: TopicContentInsets.paddingOf(context).top'),
    );
    expect(
      nested,
      contains('height: TopicContentInsets.paddingOf(context).bottom'),
    );
    final flat = File(
      'lib/pages/topic_detail_page/widgets/topic_post_list.dart',
    ).readAsStringSync();
    expect(
      flat,
      contains('topPadding: TopicContentInsets.paddingOf(context).top'),
    );
    expect(
      flat,
      contains('bottom: TopicContentInsets.paddingOf(context).bottom'),
    );
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
