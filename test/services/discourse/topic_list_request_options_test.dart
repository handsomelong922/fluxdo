import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  test('visible topic list first page uses foreground priority', () {
    final options = visibleTopicListReadOptions(page: 0);

    expect(options, isNotNull);
    expect(options!.extra!['priority'], 'high');
    expect(options.extra![skipWebViewSessionSyncExtraKey], isTrue);
  });

  test('visible topic list later pages keep foreground priority', () {
    final original = Options(extra: {'traceId': 'page-2'});
    final options = visibleTopicListReadOptions(page: 2, options: original);

    expect(options!.extra!['traceId'], 'page-2');
    expect(options.extra!['priority'], 'high');
    expect(options.extra!.containsKey(skipWebViewSessionSyncExtraKey), isFalse);
  });

  test('background read options are low priority and skip session sync', () {
    final options = backgroundReadOptionsForRequest(background: true);

    expect(options, isNotNull);
    expect(options!.extra!['priority'], 'low');
    expect(options.extra!['isSilent'], isTrue);
    expect(options.extra![skipWebViewSessionSyncExtraKey], isTrue);
  });
}
