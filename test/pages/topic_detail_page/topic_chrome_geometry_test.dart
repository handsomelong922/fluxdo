import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_bottom_bar.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_content_insets.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_overlay.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_floating_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _viewportKey = ValueKey('test-topic-viewport');
const _titleKey = ValueKey('test-topic-title');
const _tailKey = ValueKey('test-topic-tail');
const _targetKey = ValueKey('test-topic-target');
late SharedPreferences _prefs;

final _detail = TopicDetail(
  id: 1,
  title: '正文标题',
  slug: 'topic',
  postsCount: 2,
  postStream: PostStream(posts: const [], stream: const [1, 2]),
  categoryId: 1,
  closed: false,
  archived: false,
  bookmarked: false,
);

Widget _page({
  required ScrollController controller,
  required ValueNotifier<bool> showBar,
  required ValueNotifier<int> streamIndex,
  required EdgeInsets systemPadding,
  VoidCallback? onContentTap,
  bool floatingAppBar = true,
  bool centeredTarget = false,
  double keyboardHeight = 0,
}) {
  final centerKey = GlobalKey();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
    child: TranslationProvider(
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: systemPadding,
            viewPadding: systemPadding,
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          // 模拟 main.dart 已有的全局系统栏设置，不能只测 AppBar 的预设。
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
            child: child!,
          ),
        ),
        home: Scaffold(
          extendBodyBehindAppBar: floatingAppBar,
          appBar: floatingAppBar
              ? TopicFloatingAppBar(
                  brightness: Brightness.light,
                  leading: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
                  ),
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search),
                    ),
                  ],
                )
              : AppBar(title: const Text('搜索')),
          body: TopicContentBody(
            floatingAppBar: floatingAppBar,
            systemTopPadding: systemPadding.top,
            hasReply: true,
            hasProgress: true,
            child: Stack(
              children: [
                Builder(
                  builder: (context) {
                    final padding = TopicContentInsets.paddingOf(context);
                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: onContentTap,
                      child: LayoutBuilder(
                        builder: (context, constraints) => CustomScrollView(
                          key: _viewportKey,
                          controller: controller,
                          center: centeredTarget ? centerKey : null,
                          anchor: centeredTarget
                              ? topicContentAnchor(
                                  viewportAnchor: 0,
                                  topPadding: padding.top,
                                  viewportHeight: constraints.maxHeight,
                                )
                              : 0,
                          slivers: [
                            if (centeredTarget)
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 600),
                              )
                            else
                              SliverPadding(
                                padding: EdgeInsets.only(top: padding.top),
                                sliver: const SliverToBoxAdapter(
                                  child: SizedBox(
                                    key: _titleKey,
                                    height: 80,
                                    child: Text('正文标题'),
                                  ),
                                ),
                              ),
                            SliverToBoxAdapter(
                              key: centeredTarget ? centerKey : null,
                              child: const SizedBox(
                                key: _targetKey,
                                height: 1000,
                                child: Text('目标楼层'),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(
                                key: _tailKey,
                                height: 40,
                                child: Text('末尾正文'),
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.only(bottom: padding.bottom),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                TopicDetailOverlay(
                  showBottomBarListenable: showBar,
                  isLoggedIn: true,
                  streamIndexListenable: streamIndex,
                  totalCount: 2,
                  detail: _detail,
                  onScrollToTop: () {},
                  onShare: () {},
                  onOpenInBrowser: () {},
                  onReply: () {},
                  onProgressTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScrollController controller;
  late ValueNotifier<bool> showBar;
  late ValueNotifier<int> streamIndex;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    controller = ScrollController();
    showBar = ValueNotifier(true);
    streamIndex = ValueNotifier(1);
  });

  tearDown(() {
    controller.dispose();
    showBar.dispose();
    streamIndex.dispose();
  });

  void phoneSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('首帧正文避开真实状态栏和按钮，滚动时无固定工具栏占位', (tester) async {
    phoneSize(tester);
    var taps = 0;
    await tester.pumpWidget(
      _page(
        controller: controller,
        showBar: showBar,
        streamIndex: streamIndex,
        systemPadding: const EdgeInsets.only(top: 24, bottom: 34),
        onContentTap: () => taps++,
      ),
    );

    expect(tester.getTopLeft(find.byKey(_viewportKey)).dy, 24);
    expect(tester.getTopLeft(find.byKey(_titleKey)).dy, 24 + kToolbarHeight);
    await tester.tapAt(const Offset(160, 52));
    expect(taps, 1, reason: '透明顶栏空白处应透传正文手势');
    await tester.tapAt(const Offset(8, 582));
    expect(taps, 2, reason: '底栏按钮以外不应有整条遮罩拦截手势');

    controller.jumpTo(100);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_viewportKey)).dy, 24);
    expect(
      tester.getTopLeft(find.byKey(_titleKey)).dy,
      24 + kToolbarHeight - 100,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏底栏居中且只按按钮和系统安全区定高，末尾内容不被覆盖', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(
      _page(
        controller: controller,
        showBar: showBar,
        streamIndex: streamIndex,
        systemPadding: const EdgeInsets.only(top: 24, bottom: 34),
      ),
    );
    final bar = tester.getRect(find.byType(TopicBottomBar));
    expect(bar.height, kTopicBottomBarHeight + 34);
    final first = tester.getCenter(
      find.byIcon(Symbols.vertical_align_top_rounded),
    );
    final last = tester.getCenter(find.byIcon(Symbols.language_rounded));
    expect((first.dx + last.dx) / 2, 160);
    expect(first.dy, 640 - 34 - kTopicBottomBarHeight / 2);
    final reply = tester.getRect(find.byType(FloatingActionButton));
    expect(reply.bottom, lessThanOrEqualTo(bar.top));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(
      tester.getBottomLeft(find.byKey(_tailKey)).dy,
      lessThanOrEqualTo(reply.top),
    );

    showBar.value = false;
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(TopicBottomBar)).dy,
      greaterThanOrEqualTo(640),
    );
    expect(
      tester.getBottomLeft(find.byType(FloatingActionButton)).dy,
      640 - 34 - 16,
    );
    expect(tester.takeException(), isNull);
  });

  for (final keyboardHeight in [0.0, 220.0]) {
    testWidgets('中间楼层首帧按实际视口避让，键盘高度 $keyboardHeight', (tester) async {
      phoneSize(tester);
      await tester.pumpWidget(
        _page(
          controller: controller,
          showBar: showBar,
          streamIndex: streamIndex,
          systemPadding: const EdgeInsets.only(top: 24),
          centeredTarget: true,
          keyboardHeight: keyboardHeight,
        ),
      );
      expect(tester.getTopLeft(find.byKey(_targetKey)).dy, closeTo(80, 0.01));
      expect(
        tester.getSize(find.byKey(_viewportKey)).height,
        640 - 24 - keyboardHeight,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('搜索等非叠放布局不重复添加工具栏避让', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(
      _page(
        controller: controller,
        showBar: showBar,
        streamIndex: streamIndex,
        systemPadding: const EdgeInsets.only(top: 24),
        floatingAppBar: false,
      ),
    );
    expect(tester.getTopLeft(find.byKey(_viewportKey)).dy, 80);
    expect(tester.getTopLeft(find.byKey(_titleKey)).dy, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('树形超长目标的比例对齐不会把首行推到浮动按钮后面', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(
      _page(
        controller: controller,
        showBar: showBar,
        streamIndex: streamIndex,
        systemPadding: const EdgeInsets.only(top: 24),
        keyboardHeight: 220,
      ),
    );
    final target = tester.renderObject<RenderBox>(find.byKey(_targetKey));
    final viewport = RenderAbstractViewport.of(target);
    final offset = topicContentRevealOffset(
      viewport: viewport,
      target: target,
      topPadding: kToolbarHeight,
      alignment: 0.2,
    );
    controller.jumpTo(
      offset.clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      ),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_targetKey)).dy, 24 + kToolbarHeight);
    expect(tester.takeException(), isNull);
  });

  test('普通浮动顶栏透明且按主题指定原生栏图标，不请求系统遮罩', () {
    for (final brightness in Brightness.values) {
      final bar = TopicFloatingAppBar(brightness: brightness);
      final style = bar.systemOverlayStyle!;
      expect(bar.forceMaterialTransparency, isTrue);
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.scrolledUnderElevation, 0);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
      expect(
        style.statusBarIconBrightness,
        brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      );
    }
  });
}
