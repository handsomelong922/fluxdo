import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/image_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = DiscourseService();
  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late _UploadLookupAdapter adapter;

  setUp(() {
    final dio = service.dio;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = List<Interceptor>.from(dio.interceptors);
    dio.interceptors.clear();
    adapter = _UploadLookupAdapter();
    dio.httpClientAdapter = adapter;
    service.resetUploadLookupSessionState(reason: 'test_setup');
    DiscourseImageUtils.clearRuntimeCache();
  });

  tearDown(() {
    service.resetUploadLookupSessionState(reason: 'test_teardown');
    DiscourseImageUtils.clearRuntimeCache();
    final dio = service.dio;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
  });

  test('same and nearby short urls share one lookup request', () async {
    adapter.resolvedUrls.addAll({
      'upload://same.png': '/uploads/default/original/same.png',
      'upload://other.png': '/uploads/default/original/other.png',
    });

    final first = service.resolveShortUpload('upload://same.png');
    final duplicate = service.resolveShortUpload('upload://same.png');
    final other = service.resolveShortUpload('upload://other.png');

    expect(identical(first, duplicate), isTrue);
    final resolved = await Future.wait([first, duplicate, other]);

    expect(adapter.requestCount, 1);
    expect(adapter.batches.single.toSet(), {
      'upload://same.png',
      'upload://other.png',
    });
    expect(resolved[0]?.url, contains('same.png'));
    expect(resolved[1]?.url, contains('same.png'));
    expect(resolved[2]?.url, contains('other.png'));
  });

  test('successful absent result is cached as missing without retry', () async {
    adapter.resolvedUrls['upload://present.png'] =
        '/uploads/default/original/present.png';

    final resolved = await Future.wait([
      service.resolveShortUpload('upload://present.png'),
      service.resolveShortUpload('upload://missing.png'),
    ]);

    expect(resolved[0]?.isMissing, isFalse);
    expect(resolved[1]?.isMissing, isTrue);
    expect(adapter.requestCount, 1);

    final cachedMissing = await service.resolveShortUpload(
      'upload://missing.png',
    );
    expect(cachedMissing?.isMissing, isTrue);
    expect(adapter.requestCount, 1);
  });

  test('transient failure is not cached and can recover later', () async {
    adapter.failuresRemaining = 1;
    adapter.resolvedUrls['upload://retry.png'] =
        '/uploads/default/original/retry.png';

    expect(await service.resolveShortUpload('upload://retry.png'), isNull);
    expect(adapter.requestCount, 1);

    final recovered = await service.resolveShortUpload('upload://retry.png');
    expect(recovered?.url, contains('retry.png'));
    expect(adapter.requestCount, 2);
  });

  test(
    'image cache distinguishes transient failure from confirmed missing',
    () async {
      adapter.failuresRemaining = 1;
      adapter.resolvedUrls['upload://image.png'] =
          '/uploads/default/original/image.png';

      expect(
        await DiscourseImageUtils.resolveUploadUrl('upload://image.png'),
        isNull,
      );
      expect(
        DiscourseImageUtils.isUploadUrlCached('upload://image.png'),
        isFalse,
      );

      expect(
        await DiscourseImageUtils.resolveUploadUrl('upload://image.png'),
        contains('image.png'),
      );
      expect(
        DiscourseImageUtils.isUploadUrlCached('upload://image.png'),
        isTrue,
      );

      expect(
        await DiscourseImageUtils.resolveUploadUrl('upload://missing.png'),
        isNull,
      );
      expect(
        DiscourseImageUtils.isUploadUrlCached('upload://missing.png'),
        isTrue,
      );
      expect(
        DiscourseImageUtils.getCachedUploadUrl('upload://missing.png'),
        isNull,
      );
      expect(
        DiscourseImageUtils.isUploadUrlCached('upload://missing.png'),
        isTrue,
      );
    },
  );

  test('reset completes unsent batch without issuing a request', () async {
    final pending = service.resolveShortUpload('upload://pending.png');
    service.resetUploadLookupSessionState(reason: 'test_reset');

    expect(await pending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(adapter.requestCount, 0);
  });
}

class _UploadLookupAdapter implements HttpClientAdapter {
  final Map<String, String> resolvedUrls = {};
  final List<List<String>> batches = [];
  int failuresRemaining = 0;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final data = Map<String, dynamic>.from(options.data as Map);
    final shortUrls = List<String>.from(data['short_urls'] as List);
    batches.add(shortUrls);

    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'transient test failure',
      );
    }

    final response = <Map<String, dynamic>>[];
    for (final shortUrl in shortUrls) {
      final resolved = resolvedUrls[shortUrl];
      if (resolved == null) continue;
      response.add({
        'short_url': shortUrl,
        'url': resolved,
        'short_path': resolved,
      });
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
