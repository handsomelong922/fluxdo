import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/log/log_writer.dart';

void main() {
  test('defers trimming for small overshoot during normal writes', () {
    expect(
      LogWriter.shouldTrimRetention(
        entryCount: 151,
        fileSizeBytes: 1024,
        entryLimit: 150,
      ),
      isFalse,
    );
  });

  test('forces trimming once overshoot passes slack window', () {
    expect(
      LogWriter.shouldTrimRetention(
        entryCount: 176,
        fileSizeBytes: 1024,
        entryLimit: 150,
      ),
      isTrue,
    );
  });

  test('apply settings still trims immediately when forced', () {
    expect(
      LogWriter.shouldTrimRetention(
        entryCount: 151,
        fileSizeBytes: 1024,
        entryLimit: 150,
        force: true,
      ),
      isTrue,
    );
  });
}
