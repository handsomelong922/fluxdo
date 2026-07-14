import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/image_decode_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('limits concurrent work and hands slots to FIFO waiters', () async {
    final gate = ImageDecodeGate(maxInFlight: 2);
    final releases = List.generate(3, (_) => Completer<void>());
    final started = <int>[];
    var active = 0;
    var maxActive = 0;

    Future<void> task(int index) => gate.run(() async {
      started.add(index);
      active++;
      if (active > maxActive) maxActive = active;
      await releases[index].future;
      active--;
    });

    final futures = [task(0), task(1), task(2)];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1]);
    expect(gate.inFlight, 2);
    expect(gate.waitingCount, 1);

    releases[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);
    expect(maxActive, 2);

    releases[1].complete();
    releases[2].complete();
    await Future.wait(futures);
    expect(gate.inFlight, 0);
  });

  test(
    'queued first frame never calls a codec disposed while waiting',
    () async {
      final gate = ImageDecodeGate(maxInFlight: 1);
      final blocker = Completer<void>();
      final occupied = gate.run(() => blocker.future);
      await Future<void>.delayed(Duration.zero);

      final inner = _FakeCodec();
      final codec = GatedImageCodec(inner, gate: gate);
      final firstFrame = codec.getNextFrame();
      codec.dispose();
      blocker.complete();

      await expectLater(firstFrame, throwsStateError);
      await occupied;
      expect(inner.getNextFrameCalls, 0);
      expect(inner.disposeCalls, 1);
    },
  );

  test('only first frame waits for the gate', () async {
    final gate = ImageDecodeGate(maxInFlight: 1);
    final inner = _FakeCodec();
    final codec = GatedImageCodec(inner, gate: gate);

    await expectLater(codec.getNextFrame(), throwsStateError);
    expect(inner.getNextFrameCalls, 1);

    final blocker = Completer<void>();
    final occupied = gate.run(() => blocker.future);
    await Future<void>.delayed(Duration.zero);
    final secondFrame = codec.getNextFrame();
    expect(inner.getNextFrameCalls, 2);
    await expectLater(secondFrame, throwsStateError);
    blocker.complete();
    await occupied;
  });
}

class _FakeCodec implements ui.Codec {
  int getNextFrameCalls = 0;
  int disposeCalls = 0;

  @override
  int get frameCount => 2;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    getNextFrameCalls++;
    return Future<ui.FrameInfo>.error(StateError('fake frame'));
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}
