import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  test('用户主页只读请求高优先级且不阻塞 session sync', () {
    final options = visibleUserProfileReadOptions(
      options: Options(extra: {'traceId': 'profile'}),
    );

    expect(options.extra!['traceId'], 'profile');
    expect(options.extra!['priority'], 'high');
    expect(options.extra![skipWebViewSessionSyncExtraKey], isTrue);
    expect(options.extra![backgroundWebViewSessionSyncExtraKey], isTrue);
    expect(
      shouldAwaitWebViewSessionSyncForRequest(
        extra: options.extra!,
        headers: const {},
      ),
      isFalse,
    );
  });

  test('用户主页跳过阻塞等待时仍会请求后台 session sync', () {
    final options = visibleUserProfileReadOptions();

    expect(
      shouldStartBackgroundWebViewSessionSyncForRequest(
        extra: options.extra!,
        headers: const {},
      ),
      isTrue,
    );
  });

  test('现有仅 skip 请求不会被扩大为后台同步请求', () {
    expect(
      shouldStartBackgroundWebViewSessionSyncForRequest(
        extra: {skipWebViewSessionSyncExtraKey: true},
        headers: const {},
      ),
      isFalse,
    );
  });
}
