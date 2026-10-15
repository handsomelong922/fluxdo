import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/cf_challenge_logger.dart';
import 'package:fluxdo/services/cf_challenge_service.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
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
  var presentations = 0;
  final results = <bool>[];

  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    promotions = 0;
    presentations = 0;
    results.clear();
    CfChallengeLogger.setEnabled(false);
  });
  tearDown(() async {
    CfChallengeLogger.setEnabled(false);
    await platform.reset();
  });

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
                    onForegroundPresented: () => presentations++,
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
    await tester.pump(const Duration(seconds: 41));
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

  testWidgets('没有任何 WebView 回调也在四十秒后展示，初始不显示胶囊', (tester) async {
    await mount(tester, createController: false);
    expect(find.byType(DraggableFloatingPill), findsNothing);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    final element = tester.element(find.byType(InAppWebView));
    await tester.pump(const Duration(milliseconds: 39999));
    expect(promotions, 0);
    expect(presentations, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(promotions, 1);
    expect(presentations, 1);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(tester.element(find.byType(InAppWebView)), same(element));
    expect(results, isEmpty);
    await unmount(tester);
  });

  testWidgets('重复导航和页面就绪不会重置四十秒宽限', (tester) async {
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
    await tester.pump(const Duration(seconds: 30));
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
    await tester.pump(const Duration(seconds: 41));
    expect(promotions, 1, reason: '加载错误提升后取消原截止计时器');
    expect(presentations, 1, reason: '重建、重复提升不能算第二次展示');
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
    await tester.pump(const Duration(seconds: 41));
    expect(promotions, 0);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    expect(presentations, 0, reason: '后台完成没有实际展示面板');
    await unmount(tester);
  });

  testWidgets('后台探测未确认完成时保持安静，宽限到期才展示原面板', (tester) async {
    await mount(tester);
    // 现有探测按真实 DateTime 计时，在真实异步区等待它自己的八秒上限。
    // Widget 的虚拟四十秒截止没有前进，因此这里独立覆盖探测耗尽路径。
    await tester.runAsync(() async {
      await (platform.controller.handlers['onChallengeNavigation']!(const [])
          as Future<void>);
    });
    await tester.pump();
    expect(promotions, 0);
    expect(results, isEmpty);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    await tester.pump(const Duration(seconds: 40));
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
    CfChallengeLogger.setEnabled(true);
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
    expect(CfChallengeLogger.verificationMetrics['startedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['pendingRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['foregroundPresentations'], 0);
    final element = tester.element(find.byType(InAppWebView));

    var readyCompleted = false;
    final ready = service.waitForActiveVerification().then((result) {
      readyCompleted = true;
      return result;
    });
    final manual = service.showManualVerify();
    await tester.pump();
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(service.verifyRound, round);
    expect(tester.element(find.byType(InAppWebView)), same(element));
    expect(CfChallengeLogger.verificationMetrics['foregroundPresentations'], 1);
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
    expect(readyCompleted, isFalse, reason: '结果先返回，业务恢复仍需等待析构');
    expect(
      CfChallengeLogger.verificationMetrics['completedRounds'],
      0,
      reason: '等待统计要覆盖既有 readiness 门，不在页面先返回时提前结束',
    );
    // 清理服务的析构冷却、续期启动，以及前台提升提示的消失动画。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(service.isVerifying, isFalse);
    expect(await ready, isTrue);
    expect(CfChallengeLogger.verificationMetrics['startedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['succeededRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['failedRounds'], 0);
    expect(CfChallengeLogger.verificationMetrics['pendingRounds'], 0);
    await unmount(tester);
    service.resetCooldown();
  });

  Future<Future<bool?> Function()> beginServiceVerification(
    WidgetTester tester, {
    bool foreground = false,
  }) async {
    final service = CfChallengeService();
    service.resetCooldown();
    service.autoVerifyEnabled = true;
    final result = foreground
        ? service.showManualVerify()
        : service.showAutomaticVerify();
    for (var i = 0; i < 30 && platform.webView == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(platform.webView, isNotNull);
    platform.webView!.params.onWebViewCreated!(platform.controller.wrapped);
    return () => result;
  }

  void originReached() {
    platform.webView!.params.onReceivedHttpError!(
      platform.controller.wrapped,
      WebResourceRequest(url: WebUri(verifyUrl), isForMainFrame: true),
      WebResourceResponse(statusCode: 404),
    );
  }

  testWidgets('空闲等待不会创建或展示验证', (tester) async {
    await mount(tester, serviceHost: true);
    expect(await CfChallengeService().waitForActiveVerification(), isNull);
    expect(platform.webView, isNull);
    expect(find.byType(CfChallengePage), findsNothing);
    await unmount(tester);
  });

  testWidgets('四十秒内仍等待原轮次，调用方短超时不取消共享验证', (tester) async {
    await mount(tester, serviceHost: true);
    final result = await beginServiceVerification(tester);
    final service = CfChallengeService();
    final round = service.verifyRound;
    final earlyWait = service.waitForActiveVerification(
      timeout: const Duration(seconds: 12),
    );
    var readyCompleted = false;
    final ready = service.waitForActiveVerification().then((value) {
      readyCompleted = true;
      return value;
    });
    await tester.pump(const Duration(seconds: 20));
    expect(await earlyWait, isFalse);
    expect(readyCompleted, isFalse);
    expect(service.isVerifying, isTrue);
    expect(service.verifyRound, round);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    originReached();
    await tester.pump();
    expect(await result(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(await ready, isTrue);
    expect(service.isVerifying, isFalse);
    await unmount(tester);
  });

  testWidgets('原生析构后慢快照仍挡住后来等待者，快照完成自动恢复', (tester) async {
    await mount(tester, serviceHost: true);
    CfChallengeLogger.setEnabled(true);
    final result = await beginServiceVerification(tester);
    final service = CfChallengeService();
    final snapshot = Completer<List<Cookie>>();
    platform.cookies.singleValue = 'fresh';
    platform.cookies.readSnapshot = () => snapshot.future;
    originReached();
    await tester.pump();
    expect(await result(), isTrue, reason: '原始页面结果不被慢快照拖住');
    await tester.pump(const Duration(seconds: 2));
    await service.waitForManualTeardown();
    expect(find.byType(CfChallengePage), findsNothing);
    expect(service.isVerifying, isTrue, reason: '慢快照期间保持业务恢复门');
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 0);
    var lateCompleted = false;
    final late = service.waitForActiveVerification().then((value) {
      lateCompleted = true;
      return value;
    });
    await tester.pump();
    expect(lateCompleted, isFalse);
    snapshot.complete([cfTestCookie('fresh')]);
    await tester.pump();
    expect(await late, isTrue);
    expect(await service.waitForActiveVerification(), isNull);
    expect(
      await service.waitForActiveVerification(includeCompleted: true),
      isTrue,
    );
    expect(await CookieJarService().getCfClearance(), 'fresh');
    expect(service.isVerifying, isFalse);
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['succeededRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['foregroundPresentations'], 0);
    await unmount(tester);
  });

  testWidgets('快照异常关闭恢复门并返回 false，不制造异步未捕获错误', (tester) async {
    await mount(tester, serviceHost: true);
    CfChallengeLogger.setEnabled(true);
    final result = await beginServiceVerification(tester);
    final service = CfChallengeService();
    platform.cookies.singleValue = 'fresh';
    platform.cookies.readSnapshot = () =>
        Future.error(StateError('snapshot failed'));
    final ready = service.waitForActiveVerification();
    originReached();
    await tester.pump();
    expect(await result(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(await ready, isFalse);
    expect(service.isVerifying, isFalse);
    expect(await service.waitForActiveVerification(), isNull);
    expect(
      await service.waitForActiveVerification(includeCompleted: true),
      isFalse,
      reason: '页面通过但快照失败的结果不能在清理后丢失',
    );
    expect(tester.takeException(), isNull);
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['failedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['succeededRounds'], 0);
    await unmount(tester);
  });

  testWidgets('卡住的快照两分钟后释放恢复门，迟到旧快照不覆盖新值', (tester) async {
    await mount(tester, serviceHost: true);
    final result = await beginServiceVerification(tester);
    final service = CfChallengeService();
    final snapshot = Completer<List<Cookie>>();
    platform.cookies.singleValue = 'old-round';
    platform.cookies.readSnapshot = () => snapshot.future;
    final ready = service.waitForActiveVerification();
    originReached();
    await tester.pump();
    expect(await result(), isTrue);
    final cookieSync = service.waitForCompletionCookieSync();
    await tester.pump(const Duration(minutes: 2));
    expect(await ready, isFalse);
    expect(service.isVerifying, isFalse);

    await CookieJarService().cookieJar.saveFromResponse(Uri.parse(verifyUrl), [
      io.Cookie('cf_clearance', 'new-round')
        ..domain = '.linux.do'
        ..path = '/',
    ]);
    snapshot.complete([cfTestCookie('old-round')]);
    await tester.pump();
    await cookieSync;
    expect(await CookieJarService().getCfClearance(), 'new-round');
    expect(service.isVerifying, isFalse);
    await unmount(tester);
  });

  testWidgets('旧轮次等待者不能错接后来开始的验证', (tester) async {
    await mount(tester, serviceHost: true);
    final first = await beginServiceVerification(tester);
    final service = CfChallengeService();
    final firstRound = service.verifyRound;
    final capturedFirst = service.waitForActiveVerification();
    originReached();
    await tester.pump();
    expect(await first(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(await capturedFirst, isTrue);

    platform.webView = null;
    final second = await beginServiceVerification(tester);
    expect(service.verifyRound, greaterThan(firstRound));
    expect(await capturedFirst, isTrue, reason: '已经捕获的 Future 仍属于第一轮');
    expect(
      await service.waitForActiveVerification(
        includeCompleted: true,
        expectedRound: firstRound,
      ),
      isFalse,
      reason: '迟到的新等待不能采纳第二轮结果',
    );
    originReached();
    await tester.pump();
    expect(await second(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await unmount(tester);
  });

  testWidgets('显式前台不等待，普通后台入口仍保留胶囊', (tester) async {
    await mount(tester, startInBackground: false, quietBackground: false);
    expect(find.text(S.current.cf_securityVerifyTitle), findsOneWidget);
    expect(presentations, 1, reason: '初始就是前台也必须记录一次实际展示');
    expect(find.byType(DraggableFloatingPill), findsNothing);
    await unmount(tester);
    await mount(tester, quietBackground: false);
    expect(find.byType(DraggableFloatingPill), findsOneWidget);
    expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
    expect(presentations, 1, reason: '后来的后台页面尚未展示，不能增加');
    await unmount(tester);
    expect(promotions, 0, reason: '销毁后台页面后不得再弹出');
  });

  testWidgets('退出确认的打开、继续和取消只记一次展示和一轮取消', (tester) async {
    await mount(tester, serviceHost: true);
    CfChallengeLogger.setEnabled(true);
    final result = await beginServiceVerification(tester, foreground: true);
    expect(CfChallengeLogger.verificationMetrics['foregroundPresentations'], 1);
    await tester.tap(find.byTooltip(S.current.common_exit));
    await tester.pump();
    await tester.tap(find.text(S.current.cf_continueVerify));
    await tester.pump();
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 0);
    await tester.tap(find.byTooltip(S.current.common_exit));
    await tester.pump();
    await tester.tap(find.text(S.current.common_exit));
    await tester.pump();
    expect(await result(), isFalse);
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 0);
    await tester.pump(const Duration(seconds: 2));
    expect(CfChallengeLogger.verificationMetrics['completedRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['cancelledRounds'], 1);
    expect(CfChallengeLogger.verificationMetrics['failedRounds'], 0);
    expect(CfChallengeLogger.verificationMetrics['foregroundPresentations'], 1);
    await unmount(tester);
    CfChallengeService().resetCooldown();
  });

  testWidgets('未开启诊断的真实验证不采集任何统计', (tester) async {
    await mount(tester, serviceHost: true);
    final result = await beginServiceVerification(tester);
    originReached();
    await tester.pump();
    expect(await result(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(CfChallengeLogger.verificationMetrics.values, everyElement(0));
    await unmount(tester);
  });
}
