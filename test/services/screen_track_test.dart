import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/screen_track.dart';

void main() {
  test('CF business block defers timing telemetry', () {
    expect(shouldDeferScreenTrackSend(isBusinessTrafficBlocked: true), isTrue);
    expect(
      shouldDeferScreenTrackSend(isBusinessTrafficBlocked: false),
      isFalse,
    );
  });
}
