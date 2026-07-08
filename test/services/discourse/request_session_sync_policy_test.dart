import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  test('explicit skip requests never await session sync', () {
    expect(
      shouldAwaitWebViewSessionSyncForRequest(
        extra: {skipWebViewSessionSyncExtraKey: true},
        headers: const {},
      ),
      isFalse,
    );
  });

  test('background sync visible requests do not await session sync', () {
    expect(
      shouldAwaitWebViewSessionSyncForRequest(
        extra: {backgroundWebViewSessionSyncExtraKey: true},
        headers: const {},
      ),
      isFalse,
    );
  });

  test('silent background requests do not await session sync', () {
    expect(
      shouldAwaitWebViewSessionSyncForRequest(
        extra: const {'isSilent': true},
        headers: const {'Discourse-Background': 'true'},
      ),
      isFalse,
    );
  });

  test('foreground interactive requests still await session sync', () {
    expect(
      shouldAwaitWebViewSessionSyncForRequest(
        extra: const {},
        headers: const {},
      ),
      isTrue,
    );
  });
}
