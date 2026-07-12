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

  group('PerformanceDiagnosticsService frame sampling', () {
    final now = DateTime(2026, 7, 13, 0, 30);

    test('always records frozen frames and never records good frames', () {
      expect(
        PerformanceDiagnosticsService.shouldSampleFrame(
          severity: PerformanceFrameSeverity.frozen,
          now: now,
          lastSampleAt: now,
        ),
        isTrue,
      );
      expect(
        PerformanceDiagnosticsService.shouldSampleFrame(
          severity: PerformanceFrameSeverity.good,
          now: now,
        ),
        isFalse,
      );
    });

    test('uses shorter cooldowns for more severe frames', () {
      expect(
        PerformanceDiagnosticsService.frameSampleInterval(
          PerformanceFrameSeverity.severe,
        ),
        lessThan(
          PerformanceDiagnosticsService.frameSampleInterval(
            PerformanceFrameSeverity.jank,
          ),
        ),
      );
      expect(
        PerformanceDiagnosticsService.frameSampleInterval(
          PerformanceFrameSeverity.jank,
        ),
        lessThan(
          PerformanceDiagnosticsService.frameSampleInterval(
            PerformanceFrameSeverity.slow,
          ),
        ),
      );
    });

    test('samples again only after the severity cooldown expires', () {
      final lastSampleAt = now.subtract(const Duration(milliseconds: 299));
      expect(
        PerformanceDiagnosticsService.shouldSampleFrame(
          severity: PerformanceFrameSeverity.jank,
          now: now,
          lastSampleAt: lastSampleAt,
        ),
        isFalse,
      );
      expect(
        PerformanceDiagnosticsService.shouldSampleFrame(
          severity: PerformanceFrameSeverity.jank,
          now: now,
          lastSampleAt: now.subtract(const Duration(milliseconds: 300)),
        ),
        isTrue,
      );
    });
  });

  group('PerformanceFrameAttributionBuffer', () {
    test(
      'aggregates repeated builds and structured work in the same frame',
      () {
        final buffer = PerformanceFrameAttributionBuffer(maxFrames: 4);

        buffer.noteBuild(frameNumber: 12, label: 'home:topicCard#42');
        buffer.noteBuild(frameNumber: 12, label: 'home:topicCard#42');
        buffer.noteBuild(frameNumber: 12, label: 'home:excerpt#42');
        buffer.noteWork(
          frameNumber: 12,
          label: 'topic:segments',
          elapsedMicros: 5200,
          data: const {'posts': 70, 'segments': 74},
        );
        buffer.noteEvent(
          frameNumber: 12,
          label: 'image:firstFrame',
          data: const {'widthPx': 1080},
        );

        final attribution = buffer.take(12);
        expect(attribution, isNotNull);
        expect(attribution?.builds, {
          'home:topicCard#42': 2,
          'home:excerpt#42': 1,
        });
        expect(attribution?.works.single, {
          'label': 'topic:segments',
          'elapsedMicros': 5200,
          'posts': 70,
          'segments': 74,
        });
        expect(attribution?.events.single, {
          'label': 'image:firstFrame',
          'widthPx': 1080,
        });
        expect(buffer.take(12), isNull);
      },
    );

    test('evicts oldest frames and caps labels and events', () {
      final buffer = PerformanceFrameAttributionBuffer(
        maxFrames: 2,
        maxBuildLabelsPerFrame: 2,
        maxEventsPerFrame: 1,
      );

      buffer.noteBuild(frameNumber: 1, label: 'old');
      buffer.noteBuild(frameNumber: 2, label: 'first');
      buffer.noteBuild(frameNumber: 2, label: 'second');
      buffer.noteBuild(frameNumber: 2, label: 'dropped');
      buffer.noteEvent(frameNumber: 2, label: 'kept');
      buffer.noteEvent(frameNumber: 2, label: 'dropped');
      buffer.noteBuild(frameNumber: 3, label: 'new');

      expect(buffer.take(1), isNull);
      final frame = buffer.take(2);
      expect(frame?.builds.keys, ['first', 'second']);
      expect(frame?.events.single['label'], 'kept');
      expect(frame?.droppedBuildLabels, 1);
      expect(frame?.droppedEvents, 1);
      expect(buffer.length, 1);
    });
  });

  group('PerformanceDiagnosticsService attribution helpers', () {
    test('classifies the dominant slow-frame phase', () {
      expect(
        PerformanceDiagnosticsService.classifyDominantPhase(
          buildMs: 28,
          rasterMs: 5,
          vsyncOverheadMs: 2,
          queueWaitMs: 1,
        ),
        'build',
      );
      expect(
        PerformanceDiagnosticsService.classifyDominantPhase(
          buildMs: 4,
          rasterMs: 31,
          vsyncOverheadMs: 2,
          queueWaitMs: 3,
        ),
        'raster',
      );
      expect(
        PerformanceDiagnosticsService.classifyDominantPhase(
          buildMs: 4,
          rasterMs: 5,
          vsyncOverheadMs: 3,
          queueWaitMs: 45,
        ),
        'pipeline_wait',
      );
      expect(
        PerformanceDiagnosticsService.classifyDominantPhase(
          buildMs: 4,
          rasterMs: 5,
          vsyncOverheadMs: 38,
          queueWaitMs: 3,
        ),
        'vsync_overhead',
      );
    });

    test('adds actionable hints when a slow frame has no component notes', () {
      expect(
        PerformanceDiagnosticsService.buildAttributionHint(
          buildMs: 25,
          rasterMs: 4,
          attribution: null,
        ),
        'build_slow_without_component_notes',
      );
      expect(
        PerformanceDiagnosticsService.buildAttributionHint(
          buildMs: 4,
          rasterMs: 30,
          attribution: null,
        ),
        'raster_slow_without_image_events',
      );
      expect(
        PerformanceDiagnosticsService.buildAttributionHint(
          buildMs: 25,
          rasterMs: 4,
          attribution: PerformanceFrameAttribution(builds: {'post:item#3': 1}),
        ),
        isNull,
      );
    });
  });
}
