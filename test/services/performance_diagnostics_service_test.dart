import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/performance_diagnostics_service.dart';

void main() {
  group('PerformanceDiagnosticsService.classifyFrame', () {
    test('keeps short frames in the good bucket', () {
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 8,
          buildMs: 4,
          rasterMs: 4,
        ),
        PerformanceFrameSeverity.good,
      );
    });

    test('marks 60Hz-like frames as slow for 120Hz diagnosis', () {
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 17,
          buildMs: 7,
          rasterMs: 8,
        ),
        PerformanceFrameSeverity.slow,
      );
    });

    test('separates jank, severe, and frozen frames', () {
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 34,
          buildMs: 8,
          rasterMs: 8,
        ),
        PerformanceFrameSeverity.jank,
      );
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 50,
          buildMs: 8,
          rasterMs: 8,
        ),
        PerformanceFrameSeverity.severe,
      );
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 100,
          buildMs: 8,
          rasterMs: 8,
        ),
        PerformanceFrameSeverity.frozen,
      );
    });

    test('promotes expensive build or raster work to jank', () {
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 16,
          buildMs: 24,
          rasterMs: 4,
        ),
        PerformanceFrameSeverity.jank,
      );
      expect(
        PerformanceDiagnosticsService.classifyFrame(
          totalMs: 16,
          buildMs: 4,
          rasterMs: 24,
        ),
        PerformanceFrameSeverity.jank,
      );
    });
  });

  group('PerformanceDiagnosticsService.retainedTraceLines', () {
    test('keeps newest entries when count exceeds retention', () {
      final lines = List.generate(6, (index) => '{"index":$index}');

      final retained = PerformanceDiagnosticsService.retainedTraceLines(
        lines,
        maxEntries: 3,
        maxBytes: 1024,
      );

      expect(retained, ['{"index":3}', '{"index":4}', '{"index":5}']);
    });

    test('keeps newest entries when byte budget is tight', () {
      final lines = [
        '{"index":0,"message":"older"}',
        '{"index":1,"message":"newer"}',
        '{"index":2,"message":"latest"}',
      ];

      final retained = PerformanceDiagnosticsService.retainedTraceLines(
        lines,
        maxEntries: 10,
        maxBytes: 62,
      );

      expect(retained, [
        '{"index":1,"message":"newer"}',
        '{"index":2,"message":"latest"}',
      ]);
    });
  });
}
