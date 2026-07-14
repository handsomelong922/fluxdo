import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/services/message_bus_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracked topic helper predicates match new and unread semantics', () {
    const newTopic = TrackedTopicState(
      topicId: 1,
      lastReadPostNumber: null,
      highestPostNumber: 3,
      categoryId: 2,
      notificationLevel: 2,
      createdInNewPeriod: true,
      isSeen: false,
    );
    const unreadTopic = TrackedTopicState(
      topicId: 2,
      lastReadPostNumber: 4,
      highestPostNumber: 6,
      categoryId: 2,
      notificationLevel: 2,
      createdInNewPeriod: false,
      isSeen: true,
    );
    const mutedTopic = TrackedTopicState(
      topicId: 3,
      lastReadPostNumber: null,
      highestPostNumber: 2,
      categoryId: 2,
      notificationLevel: 0,
      createdInNewPeriod: true,
      isSeen: true,
    );

    expect(isTrackedTopicNew(newTopic), isTrue);
    expect(isTrackedTopicUnread(newTopic), isFalse);
    expect(isTrackedTopicUnread(unreadTopic), isTrue);
    expect(isTrackedTopicNew(unreadTopic), isFalse);
    expect(isTrackedTopicNew(mutedTopic), isFalse);
    expect(isTrackedTopicUnread(mutedTopic), isFalse);
  });

  test('latest channel only derives incoming state and keeps filters', () {
    const initial = TopicListIncomingState();
    final message = MessageBusMessage(
      channel: '/latest',
      messageId: 10,
      data: {
        'topic_id': 42,
        'message_type': 'latest',
        'payload': {'category_id': 3},
      },
    );

    final next = applyTopicListIncomingMessage(
      current: initial,
      message: message,
      mutedCategoryIds: const {},
    );
    expect(next.incomingTopics, {42: 3});

    expect(
      applyTopicListIncomingMessage(
        current: next,
        message: message,
        mutedCategoryIds: const {},
      ),
      same(next),
    );
    expect(
      applyTopicListIncomingMessage(
        current: initial,
        message: message,
        mutedCategoryIds: const {3},
      ),
      same(initial),
    );
  });

  setUp(() {
    PreloadedDataService().reset();
  });

  tearDown(() {
    PreloadedDataService().reset();
  });

  test('topicTrackingStateProvider loads lazy preloaded states', () async {
    final preloaded = PreloadedDataService();
    final html = _preloadedHtml(
      topicTrackingStates: [
        {
          'topic_id': 101,
          'last_read_post_number': null,
          'highest_post_number': 3,
          'category_id': 2,
          'notification_level': 2,
        },
        {
          'topic_id': 202,
          'last_read_post_number': 4,
          'highest_post_number': 6,
          'category_id': 3,
          'notification_level': 2,
        },
      ],
    );

    expect(await preloaded.hydrateFromHtml(html), isTrue);
    expect(preloaded.topicTrackingStatesSync, isNull);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(topicTrackingStateProvider), isEmpty);

    await _waitUntil(
      () => container.read(topicTrackingStateProvider).length == 2,
    );

    final state = container.read(topicTrackingStateProvider);
    expect(state[101]?.lastReadPostNumber, isNull);
    expect(state[101]?.highestPostNumber, 3);
    expect(state[202]?.lastReadPostNumber, 4);
    expect(state[202]?.highestPostNumber, 6);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition was not met within $timeout');
}

String _preloadedHtml({
  required List<Map<String, dynamic>> topicTrackingStates,
}) {
  final payload = jsonEncode({
    'currentUser': {'id': 1, 'username': 'tester', 'name': 'Tester'},
    'siteSettings': {'min_topic_title_length': 15, 'min_post_length': 8},
    'site': {
      'categories': <Map<String, dynamic>>[],
      'post_action_types': <Map<String, dynamic>>[],
    },
    'topicList': jsonEncode({
      'users': <Map<String, dynamic>>[],
      'topic_list': {
        'more_topics_url': null,
        'topics': <Map<String, dynamic>>[],
      },
    }),
    'topicTrackingStates': jsonEncode(topicTrackingStates),
  });
  const htmlEscape = HtmlEscape(HtmlEscapeMode.attribute);
  final escapedPayload = htmlEscape.convert(payload);

  return '''
<!doctype html>
<html>
  <head>
    <meta id="data-discourse-setup" data-cdn="https://cdn.linux.do">
  </head>
  <body>
    <div id="data-preloaded" data-preloaded="$escapedPayload"></div>
  </body>
</html>
''';
}
