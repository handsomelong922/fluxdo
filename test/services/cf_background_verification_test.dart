import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/cf_challenge_service.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:fluxdo/widgets/draggable_floating_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/cf_test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = CfTestPlatform();
  const verifyUrl = 'https://linux.do/challenge';
  var promotions = 0;
  final results = <bool>[];

  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    promotions = 0;
    results.clear();
  });
  tearDown(platform.reset);

  Future<void> mount(
    WidgetTester tester, {
    bool startInBackground = true,
    bool quietBackground = true,
    bool createController = true,
    bool serviceHost = false,
  }) async {
    SharedPreferences.setMockInitialValues({'pref_dialog_blur': false});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: serviceHost
                ? const Scaffold(body: SizedBox.shrink())
                : CfChallengePage(
                    verifyUrl: verifyUrl,
                    oldCfClearanceValues: const {},
                    startInBackground: startInBackground,
                    quietBackground: quietBackground,
                    onPromoteRequest: () => promotions++,
                    onResult: results.add,
                  ),
          ),
        ),
      ),
    );
    if (createController && !serviceHost) {
      platform.webView!.params.onWebViewCreated!(platform.controller.wrapped);
    }
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump();
    if (promotions > 0) {
      // Toast 先在仍挂载的 Overlay 上完成反向动画，避免迟到移除已销毁 entry。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull);
  }

  void loadStart() => platform.webView!.params.onLoadStart!(
    platform.controller.wrapped,
    WebUri(verifyUrl),
  );

  void pageReady() => platform.webView!.params.onPageCommitVisible!(
    platform.controller.wrapped,
    WebUri(verifyUrl),
  );

  void loadError({required bool mainFrame}) {
    platform.webView!.params.onReceivedError!(
      platform.controller.wrapped,
      WebResourceRequest(url: WebUri(verifyUrl), isForMainFrame: mainFrame),
      WebResourceError(
        type: WebResourceErrorType.HOST_LOOKUP,
        description: '测试主机无法解析',
      ),
    );
  }

  testWidgets('没有任何 WebView 回调也在十秒后展示，初始不显示胶囊', (tester) async {
    await mount(tester, createController: false);
    expect(find.byType(DraggableFloatingPill), findsNothing);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    final element = tester.element(find.byType(InAppWebView));
    await tester.pump(const Duration(milliseconds: 9999));
    expect(promotions, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(promotions, 1);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(tester.element(find.byType(InAppWebView)), same(element));
    expect(results, isEmpty);
    await unmount(tester);
  });

  testWidgets('重复导航和页面就绪不会重置十秒宽限', (tester) async {
    await mount(tester);
    platform.controller.documentHtml =
        '<html><body><div class="cf-turnstile"></div></body></html>';
    loadStart();
    pageReady();
    await tester.pump(const Duration(seconds: 4));
    loadStart();
    pageReady();
    await tester.pump(const Duration(seconds: 5));
    loadStart();
    pageReady();
    expect(promotions, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(promotions, 1);
    expect(results, isEmpty);
    await unmount(tester);
  });

  testWidgets('子资源错误保持安静，主文档错误在页面就绪前转前台', (tester) async {
    await mount(tester);
    loadError(mainFrame: false);
    await tester.pump();
    expect(promotions, 0);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    loadError(mainFrame: true);
    await tester.pump();
    expect(promotions, 1);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(results, isEmpty);
    await tester.pump(const Duration(seconds: 11));
    expect(promotions, 1, reason: '加载错误提升后取消原截止计时器');
    await unmount(tester);
  });

  testWidgets('源站提前放行后没有迟到弹窗，也不等 Cookie 续期', (tester) async {
    await mount(tester);
    platform.webView!.params.onReceivedHttpError!(
      platform.controller.wrapped,
      WebResourceRequest(url: WebUri(verifyUrl), isForMainFrame: true),
      WebResourceResponse(statusCode: 404),
    );
    await tester.pump();
    expect(results, [true]);
    await tester.pump(const Duration(seconds: 11));
    expect(promotions, 0);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    await unmount(tester);
  });

  testWidgets('后台探测未确认完成时展示原面板，不直接返回验证失败', (tester) async {
    await mount(tester);
    // 现有探测按真实 DateTime 计时，在真实异步区等待它自己的八秒上限。
    // Widget 的虚拟十秒截止没有前进，因此这里独立覆盖探测耗尽路径。
    await tester.runAsync(() async {
      await (platform.controller.handlers['onChallengeNavigation']!(const [])
          as Future<void>);
    });
    await tester.pump();
    expect(promotions, 1);
    expect(results, isEmpty);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('自动请求合流仍安静，手动加入立即提升并共享结果', (tester) async {
    final service = CfChallengeService();
    service.resetCooldown();
    service.autoVerifyEnabled = true;
    await mount(tester, serviceHost: true);
    final first = service.showAutomaticVerify();
    for (var i = 0; i < 30 && platform.webView == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(platform.webView, isNotNull);
    final round = service.verifyRound;
    final second = service.showAutomaticVerify();
    await tester.pump();
    expect(service.verifyRound, round);
    expect(find.byType(CfChallengePage), findsOneWidget);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    final element = tester.element(find.byType(InAppWebView));

    final manual = service.showManualVerify();
    await tester.pump();
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(service.verifyRound, round);
    expect(tester.element(find.byType(InAppWebView)), same(element));
    platform.webView!.params.onWebViewCreated!(platform.controller.wrapped);
    platform.webView!.params.onReceivedHttpError!(
      platform.controller.wrapped,
      WebResourceRequest(url: WebUri(verifyUrl), isForMainFrame: true),
      WebResourceResponse(statusCode: 404),
    );
    await tester.pump();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await manual, isTrue);
    // 清理服务的析构冷却、续期启动，以及前台提升提示的消失动画。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(service.isVerifying, isFalse);
    await unmount(tester);
    service.resetCooldown();
  });

  testWidgets('显式前台不等待，普通后台入口仍保留胶囊', (tester) async {
    await mount(tester, startInBackground: false, quietBackground: false);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(find.byType(DraggableFloatingPill), findsNothing);
    await unmount(tester);
    await mount(tester, quietBackground: false);
    expect(find.byType(DraggableFloatingPill), findsOneWidget);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    await unmount(tester);
    expect(promotions, 0, reason: '销毁后台页面后不得再弹出');
  });
}
