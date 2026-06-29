import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/platform_adapter.dart';
import 'package:fluxdo/services/network/adapters/webview_http_adapter.dart';
import 'package:fluxdo/services/network/webview/webview_adapter_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('requestAllowsRhttpAdapter', () {
    RequestOptions buildOptions({Map<String, dynamic>? extra}) {
      return RequestOptions(
        path: '/latest.json',
        baseUrl: 'https://linux.do',
        extra: extra ?? <String, dynamic>{},
      );
    }

    test('普通 API 请求允许走 rhttp', () {
      expect(requestAllowsRhttpAdapter(buildOptions()), isTrue);
    });

    test('显式 skipRhttpAdapter 时旁路 rhttp', () {
      expect(
        requestAllowsRhttpAdapter(
          buildOptions(extra: {'skipRhttpAdapter': true}),
        ),
        isFalse,
      );
    });
  });

  group('requestAllowsWebViewAdapter', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({'webview_adapter_enabled': true});
      await WebViewAdapterSettingsService.instance.initialize(
        await SharedPreferences.getInstance(),
      );
    });

    RequestOptions buildOptions({
      String path = '/uploads/default/original/1X/test.png',
      ResponseType responseType = ResponseType.stream,
      Map<String, dynamic>? extra,
    }) {
      return RequestOptions(
        path: path,
        baseUrl: 'https://linux.do',
        method: 'GET',
        responseType: responseType,
        extra: extra ?? <String, dynamic>{},
      );
    }

    test('主站图片 stream 请求允许走 WebView binary bridge', () {
      expect(
        requestAllowsWebViewAdapter(
          buildOptions(
            extra: {
              WebViewHttpAdapter.resourceKindExtraKey:
                  WebViewHttpAdapter.resourceKindImage,
            },
          ),
        ),
        isTrue,
      );
    });

    test('未标记为图片的二进制 stream 请求仍不走 WebView', () {
      expect(requestAllowsWebViewAdapter(buildOptions()), isFalse);
    });
  });
}
