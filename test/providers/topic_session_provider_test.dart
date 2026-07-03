import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/topic_session_provider.dart';

void main() {
  tearDown(() {
    TopicSessionNotifier.cacheRetention = const Duration(minutes: 3);
  });

  test('topicSessionProvider preserves session reads while listened', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(topicSessionProvider(42).notifier);
    notifier.markAsRead({1, 2, 3});

    expect(
      container.read(topicSessionProvider(42)).readPostNumbers,
      {1, 2, 3},
    );
  });

  test('topicSessionProvider auto-disposes after listeners leave', () async {
    TopicSessionNotifier.cacheRetention = const Duration(milliseconds: 10);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final sub = container.listen<TopicSessionState>(
      topicSessionProvider(77),
      (_, _) {},
      fireImmediately: true,
    );

    container.read(topicSessionProvider(77).notifier).markAsRead({5});
    expect(container.exists(topicSessionProvider(77)), isTrue);

    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container.pump();

    expect(container.exists(topicSessionProvider(77)), isFalse);
  });
}
