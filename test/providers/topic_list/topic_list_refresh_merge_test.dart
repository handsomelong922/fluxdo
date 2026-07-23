import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';

void main() {
  group('mergeRefreshedTopicHead', () {
    test('keeps refreshed head order and appends the existing tail', () {
      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const ['new-3', 'new-2', 'shared-1'],
        existing: const ['shared-1', 'old-4', 'old-5'],
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, ['new-3', 'new-2', 'shared-1', 'old-4', 'old-5']);
    });

    test('deduplicates repeated ids in both inputs', () {
      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const ['fresh-1', 'duplicate-1', 'fresh-2'],
        existing: const ['old-2', 'old-3', 'duplicate-3'],
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, ['fresh-1', 'fresh-2', 'old-3']);
    });

    test('returns a detached copy when refreshed head is empty', () {
      final existing = <String>['old-1', 'old-2'];

      final merged = mergeRefreshedTopicHead<String, int>(
        refreshed: const [],
        existing: existing,
        idOf: (item) => int.parse(item.split('-').last),
      );

      expect(merged, existing);
      expect(identical(merged, existing), isFalse);
    });
  });

  group('preserveRefreshedPagination', () {
    test('does not move the loaded page backwards after head refresh', () {
      final result = preserveRefreshedPagination(
        previousPage: 5,
        previousHasMore: false,
        refreshedPage: 0,
        refreshedHasMore: true,
      );

      expect(result.page, 5);
      expect(result.hasMore, isTrue);
    });

    test('keeps a newer refreshed page and combines has-more state', () {
      final result = preserveRefreshedPagination(
        previousPage: 1,
        previousHasMore: true,
        refreshedPage: 2,
        refreshedHasMore: false,
      );

      expect(result.page, 2);
      expect(result.hasMore, isTrue);
    });
  });

  group('load-more recovery contracts', () {
    test('successful filtered or duplicate pages still advance the cursor', () {
      expect(
        topicListPageAfterSuccessfulLoad(
          previousPage: 0,
          requestedPage: 1,
          mergedItemCount: 20,
          previousItemCount: 20,
        ),
        1,
      );
      expect(
        topicListPageAfterSuccessfulLoad(
          previousPage: 1,
          requestedPage: 2,
          mergedItemCount: 20,
          previousItemCount: 20,
        ),
        2,
      );
    });

    test('transient failures are retryable after cooldown without a timer', () {
      final retryAt = DateTime.utc(2026, 7, 23, 8, 0, 2);

      expect(
        canRetryTopicListLoadMoreNow(
          failed: true,
          requiresManualRetry: false,
          retryAfter: retryAt,
          now: DateTime.utc(2026, 7, 23, 8, 0, 1),
        ),
        isFalse,
      );
      expect(
        canRetryTopicListLoadMoreNow(
          failed: true,
          requiresManualRetry: false,
          retryAfter: retryAt,
          now: DateTime.utc(2026, 7, 23, 8, 0, 2),
        ),
        isTrue,
      );
    });

    test('manual failures stay blocked until explicit retry', () {
      expect(
        canRetryTopicListLoadMoreNow(
          failed: true,
          requiresManualRetry: true,
          retryAfter: null,
          now: DateTime.utc(2026, 7, 23, 8, 0, 30),
        ),
        isFalse,
      );
    });

    test('classifies network and server failures as transient', () {
      final options = RequestOptions(path: '/latest.json');
      expect(
        isTransientTopicListLoadMoreError(TimeoutException('slow')),
        isTrue,
      );
      expect(isTransientTopicListLoadMoreError(ServerException(503)), isTrue);
      expect(
        isTransientTopicListLoadMoreError(
          DioException.badResponse(
            statusCode: 500,
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 500),
          ),
        ),
        isTrue,
      );
    });

    test('keeps rate limits, auth and Cloudflare behind manual retry', () {
      final options = RequestOptions(path: '/latest.json');
      expect(
        requiresManualTopicListLoadMoreRetry(
          DioException.badResponse(
            statusCode: 429,
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 429),
          ),
        ),
        isTrue,
      );
      expect(
        requiresManualTopicListLoadMoreRetry(
          DioException.badResponse(
            statusCode: 401,
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
          ),
        ),
        isTrue,
      );
      expect(
        requiresManualTopicListLoadMoreRetry(CfChallengeException()),
        isTrue,
      );
      expect(
        requiresManualTopicListLoadMoreRetry(RateLimitException(10)),
        isTrue,
      );
      expect(
        requiresManualTopicListLoadMoreRetry(
          const FormatException('malformed response'),
        ),
        isTrue,
      );
    });
  });
}
