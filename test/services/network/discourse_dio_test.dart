import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/discourse_dio.dart';
import 'package:fluxdo/services/network/request_scheduler_config.dart';

void main() {
  group('shouldRetryDiscourseRequest', () {
    RequestOptions options(String method) =>
        RequestOptions(path: '/latest.json', method: method);

    test('retries transient read request failures', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException.connectionError(
            requestOptions: options('GET'),
            reason: 'socket closed',
          ),
          1,
        ),
        isTrue,
      );

      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('HEAD'),
            type: DioExceptionType.receiveTimeout,
          ),
          1,
        ),
        isTrue,
      );
    });

    test('retries selected read response statuses', () {
      for (final statusCode in [408, 502, 503, 504]) {
        final requestOptions = options('GET');

        expect(
          shouldRetryDiscourseRequest(
            DioException.badResponse(
              statusCode: statusCode,
              requestOptions: requestOptions,
              response: Response(
                requestOptions: requestOptions,
                statusCode: statusCode,
              ),
            ),
            1,
          ),
          isTrue,
        );
      }
    });

    test('does not retry rate limits', () {
      final requestOptions = options('GET');

      expect(
        shouldRetryDiscourseRequest(
          DioException.badResponse(
            statusCode: 429,
            requestOptions: requestOptions,
            response: Response(requestOptions: requestOptions, statusCode: 429),
          ),
          1,
        ),
        isFalse,
      );
    });

    test('does not retry write requests', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException.connectionError(
            requestOptions: options('POST'),
            reason: 'socket closed',
          ),
          1,
        ),
        isFalse,
      );
    });

    test('does not retry definitive failures', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('GET'),
            type: DioExceptionType.cancel,
          ),
          1,
        ),
        isFalse,
      );

      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('GET'),
            type: DioExceptionType.badCertificate,
            error: const CertificateException('bad cert'),
          ),
          1,
        ),
        isFalse,
      );
    });
  });

  group('RequestSchedulerConfig', () {
    test(
      'pauses new requests after server rate limits and clears after expiry',
      () async {
        RequestSchedulerConfig.pauseFor(const Duration(milliseconds: 30));

        expect(
          RequestSchedulerConfig.serverCooldownRemaining.inMicroseconds,
          greaterThan(0),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(RequestSchedulerConfig.serverCooldownRemaining, Duration.zero);
      },
    );
  });
}
