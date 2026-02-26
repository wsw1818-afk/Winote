import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:winote/core/services/stroke_smoothing_service.dart';
import 'package:winote/core/services/stroke_cache_service.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';

void main() {
  group('필기 지연 시간 테스트', () {
    late StrokeSmoothingService smoothingService;
    late StrokeCacheService cacheService;

    setUp(() {
      smoothingService = StrokeSmoothingService.instance;
      cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
    });

    tearDown(() {
      cacheService.clearAll();
    });

    test('단일 포인트 추가 지연 시간 (목표: < 1ms)', () {
      final stopwatch = Stopwatch();
      final points = <StrokePoint>[];

      // 100개 포인트 추가 시간 측정
      stopwatch.start();
      for (int i = 0; i < 100; i++) {
        points.add(StrokePoint(
          x: 100.0 + i * 2,
          y: 100.0 + i,
          pressure: 0.5,
          tilt: 0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),);
      }
      stopwatch.stop();

      final avgMicroseconds = stopwatch.elapsedMicroseconds / 100;
      print('포인트 추가 평균 시간: ${avgMicroseconds.toStringAsFixed(2)}µs');

      // 각 포인트 추가가 100µs (0.1ms) 이하여야 함
      expect(avgMicroseconds, lessThan(100));
    });

    test('스트로크 스무딩 지연 시간 (목표: < 5ms)', () {
      // 테스트용 스트로크 생성 (50 포인트)
      final points = _createTestPoints(50);

      final stopwatch = Stopwatch()..start();

      // 스무딩 적용
      final smoothedPoints = smoothingService.smoothStroke(points);

      stopwatch.stop();

      print('스무딩 처리 시간 (50pts): ${stopwatch.elapsedMilliseconds}ms');
      print('스무딩 후 포인트 수: ${smoothedPoints.length}');

      // 50포인트 스무딩이 5ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(5));
    });

    test('대량 포인트 스무딩 지연 시간 (100 포인트)', () {
      final points = _createTestPoints(100);

      final stopwatch = Stopwatch()..start();
      final smoothedPoints = smoothingService.smoothStroke(points);
      stopwatch.stop();

      print('스무딩 처리 시간 (100pts): ${stopwatch.elapsedMilliseconds}ms');
      print('스무딩 후 포인트 수: ${smoothedPoints.length}');

      // 100포인트 스무딩이 10ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });

    test('장문 스트로크 스무딩 지연 시간 (500 포인트)', () {
      final points = _createTestPoints(500);

      final stopwatch = Stopwatch()..start();
      final smoothedPoints = smoothingService.smoothStroke(points);
      stopwatch.stop();

      print('스무딩 처리 시간 (500pts): ${stopwatch.elapsedMilliseconds}ms');
      print('스무딩 후 포인트 수: ${smoothedPoints.length}');

      // 500포인트 스무딩이 50ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('실시간 포인트 추가 시뮬레이션 (60fps 기준)', () {
      // 60fps = 16.67ms per frame
      // 1초간 필기 = 60 프레임 = 약 180 포인트 (3pts/frame 가정)

      final points = <StrokePoint>[];
      final frameTimes = <int>[];

      for (int frame = 0; frame < 60; frame++) {
        final frameStopwatch = Stopwatch()..start();

        // 프레임당 3개 포인트 추가
        for (int p = 0; p < 3; p++) {
          points.add(StrokePoint(
            x: 100.0 + frame * 5 + p * 2,
            y: 100.0 + frame * 3 + p,
            pressure: 0.5 + (p * 0.1),
            tilt: 0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),);
        }

        frameStopwatch.stop();
        frameTimes.add(frameStopwatch.elapsedMicroseconds);
      }

      final avgFrameTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;
      final maxFrameTime = frameTimes.reduce((a, b) => a > b ? a : b);

      print('평균 프레임 처리 시간: ${avgFrameTime.toStringAsFixed(2)}µs');
      print('최대 프레임 처리 시간: $maxFrameTimeµs');
      print('총 포인트 수: ${points.length}');

      // 프레임 처리가 1ms (1000µs) 이하여야 60fps 유지 가능
      expect(avgFrameTime, lessThan(1000));
    });

    test('스트로크 완료 후 캐시 저장 지연 시간', () async {
      final stroke = _createTestStroke(100);
      const canvasSize = Size(1920, 1080);

      final stopwatch = Stopwatch()..start();
      await cacheService.cacheStrokes([stroke], canvasSize, null);
      stopwatch.stop();

      print('캐시 저장 시간 (1 스트로크, 100pts): ${stopwatch.elapsedMilliseconds}ms');

      // 캐시 저장이 100ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('연속 스트로크 캐시 갱신 지연 시간', () async {
      const canvasSize = Size(1920, 1080);
      final updateTimes = <int>[];

      // 10개 스트로크를 순차적으로 추가하며 캐시 갱신
      final strokes = <Stroke>[];
      for (int i = 0; i < 10; i++) {
        strokes.add(_createTestStroke(50, id: 'stroke-$i'));

        cacheService.invalidateCache();
        final stopwatch = Stopwatch()..start();
        await cacheService.cacheStrokes(strokes, canvasSize, null);
        stopwatch.stop();

        updateTimes.add(stopwatch.elapsedMilliseconds);
      }

      print('캐시 갱신 시간 (스트로크 수 증가):');
      for (int i = 0; i < updateTimes.length; i++) {
        print('  ${i + 1}개 스트로크: ${updateTimes[i]}ms');
      }

      // 마지막 갱신 (10개 스트로크)도 200ms 이하여야 함
      expect(updateTimes.last, lessThan(200));
    });

    test('필압 처리 지연 시간', () {
      final stroke = _createTestStroke(100);

      final stopwatch = Stopwatch()..start();

      // 필압 기반 굵기 계산
      for (final point in stroke.points) {
        final width = stroke.getWidthAtPressure(point.pressure);
        // 계산 결과 사용 (최적화 방지)
        expect(width, greaterThan(0));
      }

      stopwatch.stop();

      print('필압 처리 시간 (100pts): ${stopwatch.elapsedMicroseconds}µs');

      // 100포인트 필압 처리가 1ms 이하여야 함
      expect(stopwatch.elapsedMicroseconds, lessThan(1000));
    });
  });

  group('입력 이벤트 처리 시뮬레이션', () {
    test('포인터 이벤트 처리 속도 (PointerMoveEvent 시뮬레이션)', () {
      final stopwatch = Stopwatch();
      final events = <Duration>[];

      // 100개 포인터 이벤트 시뮬레이션
      for (int i = 0; i < 100; i++) {
        stopwatch.reset();
        stopwatch.start();

        // 이벤트 데이터 생성 (실제 앱에서 발생하는 처리)
        final position = Offset(100.0 + i * 2, 100.0 + i);
        final pressure = 0.5 + (i % 10) * 0.05;
        final timestamp = DateTime.now();

        // 포인트 변환
        final point = StrokePoint(
          x: position.dx,
          y: position.dy,
          pressure: pressure,
          tilt: 0,
          timestamp: timestamp.millisecondsSinceEpoch,
        );

        stopwatch.stop();
        events.add(stopwatch.elapsed);

        // 결과 사용 (최적화 방지)
        expect(point.x, equals(position.dx));
      }

      final avgMicros = events.map((e) => e.inMicroseconds).reduce((a, b) => a + b) / events.length;
      print('포인터 이벤트 처리 평균 시간: ${avgMicros.toStringAsFixed(2)}µs');

      // 각 이벤트 처리가 200µs 이하여야 함
      expect(avgMicros, lessThan(200));
    });

    test('바운딩 박스 업데이트 지연 시간', () {
      final points = _createTestPoints(100);

      final stopwatch = Stopwatch()..start();

      // 바운딩 박스 계산 시뮬레이션
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;

      for (final point in points) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
      }

      stopwatch.stop();

      print('바운딩 박스 계산 시간 (100pts): ${stopwatch.elapsedMicroseconds}µs');

      // 100포인트 바운딩 박스 계산이 100µs 이하여야 함
      expect(stopwatch.elapsedMicroseconds, lessThan(100));
    });
  });

  group('렌더링 지연 시간 테스트', () {
    test('스트로크 Path 생성 지연 시간', () {
      final points = _createTestPoints(100);

      final stopwatch = Stopwatch()..start();

      // Path 생성
      final path = ui.Path();
      path.moveTo(points.first.x, points.first.y);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].x, points[i].y);
      }

      stopwatch.stop();

      print('Path 생성 시간 (100pts): ${stopwatch.elapsedMicroseconds}µs');

      // 100포인트 Path 생성이 2000µs (2ms) 이하여야 함
      expect(stopwatch.elapsedMicroseconds, lessThan(2000));
    });

    test('베지어 곡선 Path 생성 지연 시간', () {
      final points = _createTestPoints(100);

      final stopwatch = Stopwatch()..start();

      // 베지어 곡선 Path 생성
      final path = ui.Path();
      path.moveTo(points.first.x, points.first.y);

      for (int i = 1; i < points.length - 1; i++) {
        final p0 = points[i - 1];
        final p1 = points[i];
        final p2 = points[i + 1];

        final midX = (p1.x + p2.x) / 2;
        final midY = (p1.y + p2.y) / 2;

        path.quadraticBezierTo(p1.x, p1.y, midX, midY);
      }

      stopwatch.stop();

      print('베지어 Path 생성 시간 (100pts): ${stopwatch.elapsedMicroseconds}µs');

      // 100포인트 베지어 Path가 1000µs (1ms) 이하여야 함
      expect(stopwatch.elapsedMicroseconds, lessThan(1000));
    });

    test('다중 스트로크 렌더링 준비 지연 시간', () {
      // 10개 스트로크, 각 50 포인트
      final strokes = List.generate(10, (i) => _createTestStroke(50, id: 'stroke-$i'));

      final stopwatch = Stopwatch()..start();

      // 모든 스트로크 Path 생성
      final paths = <ui.Path>[];
      for (final stroke in strokes) {
        final path = ui.Path();
        if (stroke.points.isNotEmpty) {
          path.moveTo(stroke.points.first.x, stroke.points.first.y);
          for (int i = 1; i < stroke.points.length; i++) {
            path.lineTo(stroke.points[i].x, stroke.points[i].y);
          }
        }
        paths.add(path);
      }

      stopwatch.stop();

      print('다중 스트로크 Path 생성 시간 (10개, 각 50pts): ${stopwatch.elapsedMilliseconds}ms');

      // 10개 스트로크 Path 생성이 15ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });
  });

  group('메모리 효율성 테스트', () {
    test('대량 포인트 메모리 사용량 추정', () {
      // StrokePoint 크기: x(8) + y(8) + pressure(8) + tilt(8) + timestamp(8) = 40 bytes
      const pointSize = 40; // bytes (추정)
      const pointCount = 10000;

      final points = _createTestPoints(pointCount);

      const estimatedMemory = pointCount * pointSize;
      print('$pointCount개 포인트 예상 메모리: ${(estimatedMemory / 1024).toStringAsFixed(2)} KB');

      expect(points.length, equals(pointCount));
    });

    test('스트로크 객체 생성/소멸 사이클', () {
      final stopwatch = Stopwatch()..start();

      // 100개 스트로크 생성 및 소멸
      for (int i = 0; i < 100; i++) {
        final stroke = _createTestStroke(50, id: 'temp-$i');
        // 사용 (최적화 방지)
        expect(stroke.points.length, equals(50));
      }

      stopwatch.stop();

      print('100개 스트로크 생성/소멸 시간: ${stopwatch.elapsedMilliseconds}ms');

      // 100개 스트로크 사이클이 50ms 이하여야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('종합 필기 시나리오 테스트', () {
    test('1초간 필기 시뮬레이션 (60fps, 3pts/frame)', () {
      final totalStopwatch = Stopwatch()..start();
      final frameLatencies = <int>[];

      final stroke = Stroke(
        id: 'simulation-stroke',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final points = <StrokePoint>[];

      // 60프레임 시뮬레이션
      for (int frame = 0; frame < 60; frame++) {
        final frameStopwatch = Stopwatch()..start();

        // 포인트 추가
        for (int p = 0; p < 3; p++) {
          points.add(StrokePoint(
            x: 100.0 + frame * 5 + p * 2,
            y: 100.0 + frame * 3 + p,
            pressure: 0.5 + (p * 0.1),
            tilt: 0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),);
        }

        frameStopwatch.stop();
        frameLatencies.add(frameStopwatch.elapsedMicroseconds);
      }

      totalStopwatch.stop();

      final avgLatency = frameLatencies.reduce((a, b) => a + b) / frameLatencies.length;
      final maxLatency = frameLatencies.reduce((a, b) => a > b ? a : b);
      final minLatency = frameLatencies.reduce((a, b) => a < b ? a : b);

      print('=== 1초 필기 시뮬레이션 결과 ===');
      print('총 소요 시간: ${totalStopwatch.elapsedMilliseconds}ms');
      print('총 포인트 수: ${points.length}');
      print('프레임 평균 지연: ${avgLatency.toStringAsFixed(2)}µs');
      print('프레임 최대 지연: $maxLatencyµs');
      print('프레임 최소 지연: $minLatencyµs');

      // 평균 프레임 지연이 1000µs 이하면 60fps 충분히 유지 가능
      expect(avgLatency, lessThan(1000));

      // 최대 지연도 5ms 이하여야 함 (프레임 드랍 방지)
      expect(maxLatency, lessThan(5000));
    });

    test('필기 완료 후 전체 처리 파이프라인', () async {
      final points = _createTestPoints(100);

      // 1. 스무딩
      final smoothStopwatch = Stopwatch()..start();
      final smoothedPoints = StrokeSmoothingService.instance.smoothStroke(points);
      smoothStopwatch.stop();

      // 2. 스트로크 생성
      final strokeStopwatch = Stopwatch()..start();
      final stroke = Stroke(
        id: 'final-stroke',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: smoothedPoints,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      strokeStopwatch.stop();

      // 3. 캐시 갱신
      final cacheStopwatch = Stopwatch()..start();
      StrokeCacheService.instance.invalidateCache();
      await StrokeCacheService.instance.cacheStrokes(
        [stroke],
        const Size(1920, 1080),
        null,
      );
      cacheStopwatch.stop();

      final totalTime = smoothStopwatch.elapsedMilliseconds +
                       strokeStopwatch.elapsedMilliseconds +
                       cacheStopwatch.elapsedMilliseconds;

      print('=== 필기 완료 처리 파이프라인 ===');
      print('1. 스무딩: ${smoothStopwatch.elapsedMilliseconds}ms');
      print('2. 스트로크 생성: ${strokeStopwatch.elapsedMilliseconds}ms');
      print('3. 캐시 갱신: ${cacheStopwatch.elapsedMilliseconds}ms');
      print('총 처리 시간: ${totalTime}ms');

      // 전체 처리가 200ms 이하여야 사용자가 지연을 느끼지 않음
      expect(totalTime, lessThan(200));

      StrokeCacheService.instance.clearAll();
    });
  });
}

/// 테스트용 포인트 생성
List<StrokePoint> _createTestPoints(int count) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return List.generate(count, (i) => StrokePoint(
    x: 100.0 + i * 3,
    y: 100.0 + (i * 2) + (i % 5) * 0.5, // 약간의 곡선
    pressure: 0.5 + (i % 10) * 0.05,
    tilt: 0,
    timestamp: now + i,
  ),);
}

/// 테스트용 스트로크 생성
Stroke _createTestStroke(int pointCount, {String id = 'test-stroke'}) {
  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: _createTestPoints(pointCount),
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}
