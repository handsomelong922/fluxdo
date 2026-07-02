import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/external_browser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = ExternalBrowserService.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    ExternalBrowserService.debugIsAndroidOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('listAvailableBrowsers parses native browser list', () async {
    ExternalBrowserService.debugIsAndroidOverride = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listBrowsers');
      return <Map<String, String>>[
        {'packageName': 'com.android.chrome', 'label': 'Chrome'},
        {'packageName': 'org.mozilla.firefox', 'label': 'Firefox'},
      ];
    });

    final browsers = await ExternalBrowserService.listAvailableBrowsers();

    expect(browsers, hasLength(2));
    expect(browsers.first.packageName, 'com.android.chrome');
    expect(browsers.first.label, 'Chrome');
    expect(browsers.last.packageName, 'org.mozilla.firefox');
  });

  test(
    'openUrl forwards preferred browser package to native channel',
    () async {
      ExternalBrowserService.debugIsAndroidOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openInBrowser');
        expect(call.arguments, <String, dynamic>{
          'url': 'https://linux.do',
          'packageName': 'com.android.chrome',
        });
        return true;
      });

      final launched = await ExternalBrowserService.openUrl(
        'https://linux.do',
        packageName: 'com.android.chrome',
      );

      expect(launched, isTrue);
    },
  );
}
