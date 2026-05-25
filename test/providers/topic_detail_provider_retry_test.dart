import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';

void main() {
  group('isRetryableTopicInitialLoadError', () {
    RequestOptions options() => RequestOptions(path: '/t/42.json');

    test('retries transient Dio failures and timeouts', () {
      expect(
        isRetryableTopicInitialLoadError(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.cancel,
          ),
        ),
        isTrue,
      );
      expect(
        isRetryableTopicInitialLoadError(
          DioException.connectionError(
            requestOptions: options(),
            reason: 'socket closed',
          ),
        ),
        isTrue,
      );
      expect(
        isRetryableTopicInitialLoadError(TimeoutException('slow')),
        isTrue,
      );
    });

    test('retries rate limit and gateway/server availability responses', () {
      for (final statusCode in [429, 502, 503, 504]) {
        expect(
          isRetryableTopicInitialLoadError(
            DioException.badResponse(
              statusCode: statusCode,
              requestOptions: options(),
              response: Response(
                requestOptions: options(),
                statusCode: statusCode,
              ),
            ),
          ),
          isTrue,
        );
      }
    });

    test('does not retry definitive client or auth responses', () {
      for (final statusCode in [400, 401, 403, 404, 422]) {
        expect(
          isRetryableTopicInitialLoadError(
            DioException.badResponse(
              statusCode: statusCode,
              requestOptions: options(),
              response: Response(
                requestOptions: options(),
                statusCode: statusCode,
              ),
            ),
          ),
          isFalse,
        );
      }
    });
  });
}
