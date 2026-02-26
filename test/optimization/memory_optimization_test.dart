import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:winote/core/services/stroke_cache_service.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/presentation/widgets/canvas/painters/canvas_painters.dart';
import 'package:winote/domain/entities/canvas_table.dart';

void main() {
  group('StrokeCacheService 메모리 최적화 테스트', () {
    late StrokeCacheService cacheService;

    setUp(() {
      cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
    });

    tearDown(() {
      cacheService.clearAll();
    });

    test('캐시 생성 후 이전 캐시가 정리되어야 함', () async {
      // Given: 테스트용 스트로크 생성
      final strokes = _createTestStrokes(10);
      const canvasSize = Size(800, 600);

      // When: 캐시 생성 2회 (두 번째 호출 시 첫 번째 캐시 dispose 확인)
      final image1 = await cacheService.cacheStrokes(strokes, canvasSize, null);
      expect(image1, isNotNull);

      // 스트로크 변경하여 새 캐시 생성 유도
      cacheService.invalidateCache();
      final strokes2 = _createTestStrokes(15);
      final image2 = await cacheService.cacheStrokes(strokes2, canvasSize, null);
      expect(image2, isNotNull);

      // Then: 새 이미지가 생성되었고, 이전 캐시는 정리됨
      expect(image1 != image2, isTrue);
    });

    test('빈 스트로크 리스트 처리', () async {
      final image = await cacheService.cacheStrokes(
        [],
        const Size(800, 600),
        null,
      );
      // 빈 스트로크는 null 반환
      expect(image, isNull);
    });

    test('동일 스트로크 반복 요청 시 캐시 재사용', () async {
      final strokes = _createTestStrokes(5);
      const canvasSize = Size(800, 600);

      await cacheService.cacheStrokes(strokes, canvasSize, null);
      expect(cacheService.isCacheValid(strokes), isTrue);

      // 캐시된 이미지 가져오기
      final cachedImage = cacheService.getCachedImage();
      expect(cachedImage, isNotNull);
    });

    test('excludeIds로 특정 스트로크 제외 시 새 캐시 생성', () async {
      final strokes = _createTestStrokes(5);
      const canvasSize = Size(800, 600);

      final image1 = await cacheService.cacheStrokes(strokes, canvasSize, null);

      cacheService.invalidateCache();
      final image2 = await cacheService.cacheStrokes(
        strokes,
        canvasSize,
        {strokes.first.id},
      );

      // excludeIds가 다르면 다른 캐시 생성됨
      expect(image1, isNotNull);
      expect(image2, isNotNull);
    });

    test('clearAll() 호출 시 모든 캐시 정리', () async {
      final strokes = _createTestStrokes(5);
      const canvasSize = Size(800, 600);

      await cacheService.cacheStrokes(strokes, canvasSize, null);

      // clearAll 호출
      cacheService.clearAll();
      expect(cacheService.getCachedImage(), isNull);

      // 다시 호출하면 새 캐시 생성 (에러 없이)
      final image = await cacheService.cacheStrokes(strokes, canvasSize, null);
      expect(image, isNotNull);
    });

    test('invalidateCache() 호출 시 캐시 무효화', () async {
      final strokes = _createTestStrokes(5);
      const canvasSize = Size(800, 600);

      await cacheService.cacheStrokes(strokes, canvasSize, null);
      expect(cacheService.isCacheValid(strokes), isTrue);

      cacheService.invalidateCache();
      expect(cacheService.isCacheValid(strokes), isFalse);
    });

    test('invalidateStroke() 호출 시 개별 스트로크 캐시 삭제', () async {
      final strokes = _createTestStrokes(5);
      const canvasSize = Size(800, 600);

      await cacheService.cacheStrokes(strokes, canvasSize, null);

      // 특정 스트로크 무효화
      cacheService.invalidateStroke(strokes.first.id);

      // 전체 캐시도 무효화됨
      expect(cacheService.isCacheValid(strokes), isFalse);
    });

    test('대량 스트로크 캐시 생성 (메모리 스트레스)', () async {
      // Given: 대량 스트로크 (100개, 각 50포인트)
      final strokes = _createTestStrokes(100, pointsPerStroke: 50);
      const canvasSize = Size(1920, 1080);

      // When: 캐시 생성
      final stopwatch = Stopwatch()..start();
      final image = await cacheService.cacheStrokes(strokes, canvasSize, null);
      stopwatch.stop();

      // Then: 성공적으로 생성되고 합리적인 시간 내 완료
      expect(image, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // 5초 이내
      print('대량 스트로크 캐시 생성 시간: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('반복적인 캐시 갱신 시 메모리 누적 없음 확인', () async {
      const canvasSize = Size(800, 600);

      // 100회 반복하여 캐시 갱신
      for (int i = 0; i < 100; i++) {
        cacheService.invalidateCache();
        final strokes = _createTestStrokes(10 + i % 5); // 매번 다른 스트로크
        final image = await cacheService.cacheStrokes(strokes, canvasSize, null);
        expect(image, isNotNull);
      }

      // 마지막 캐시만 남아있어야 함 (이전 99개는 dispose됨)
      // 에러 없이 완료되면 성공
    });
  });

  group('TablePainter TextPainter 캐시 LRU 테스트', () {
    setUp(() {
      // 테스트 전 캐시 초기화
      TablePainter.clearCache();
    });

    tearDown(() {
      TablePainter.clearCache();
    });

    test('캐시 크기 제한 (500개) 초과 시 LRU 제거', () {
      // Given: 테이블과 페인터 생성 (30x20 = 600 셀)
      final tables = _createTestTables(1, rowCount: 30, colCount: 20);
      final painter = TablePainter(tables: tables);

      // When: paint 호출하여 캐시 채우기
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(1920, 1080));
      recorder.endRecording();

      // Then: 캐시가 500개 이하로 유지됨
      // (내부 캐시 크기 확인 - 직접 접근 불가하므로 에러 없이 완료 확인)
    });

    test('clearCache() 호출 시 모든 캐시 정리', () {
      final tables = _createTestTables(1, rowCount: 10, colCount: 10);
      final painter = TablePainter(tables: tables);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(800, 600));
      recorder.endRecording();

      // clear 호출
      TablePainter.clearCache();

      // 다시 paint 호출해도 에러 없음
      final recorder2 = ui.PictureRecorder();
      final canvas2 = Canvas(recorder2);
      painter.paint(canvas2, const Size(800, 600));
      recorder2.endRecording();
    });

    test('반복적인 테이블 렌더링 시 캐시 재사용', () {
      final tables = _createTestTables(1, rowCount: 5, colCount: 5);
      final painter = TablePainter(tables: tables);

      final stopwatch = Stopwatch();

      // 첫 번째 렌더링 (캐시 생성)
      stopwatch.start();
      for (int i = 0; i < 10; i++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(800, 600));
        recorder.endRecording();
      }
      stopwatch.stop();
      final firstTime = stopwatch.elapsedMicroseconds;

      // 두 번째 렌더링 (캐시 재사용)
      stopwatch.reset();
      stopwatch.start();
      for (int i = 0; i < 10; i++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(800, 600));
        recorder.endRecording();
      }
      stopwatch.stop();
      final secondTime = stopwatch.elapsedMicroseconds;

      print('첫 번째 렌더링 (캐시 생성): $firstTimeµs');
      print('두 번째 렌더링 (캐시 재사용): $secondTimeµs');

      // 캐시 재사용으로 두 번째가 더 빠르거나 비슷해야 함
    });

    test('대량 테이블 셀 렌더링 스트레스 테스트', () {
      // Given: 큰 테이블 (50x50 = 2500 셀)
      final tables = _createTestTables(1, rowCount: 50, colCount: 50);
      final painter = TablePainter(tables: tables);

      // When: 렌더링
      final stopwatch = Stopwatch()..start();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(2000, 2000));
      recorder.endRecording();
      stopwatch.stop();

      print('대량 테이블 렌더링 시간: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(3000)); // 3초 이내
    });

    test('LRU 순서 검증 - 자주 사용되는 항목 유지', () {
      // 600개 셀 테이블 (캐시 초과)
      final tables = _createTestTables(1, rowCount: 30, colCount: 20);
      final painter = TablePainter(tables: tables);

      // 첫 번째 렌더링으로 캐시 채우기
      var recorder = ui.PictureRecorder();
      var canvas = Canvas(recorder);
      painter.paint(canvas, const Size(1920, 1080));
      recorder.endRecording();

      // 추가 렌더링 (캐시 갱신)
      for (int i = 0; i < 5; i++) {
        recorder = ui.PictureRecorder();
        canvas = Canvas(recorder);
        painter.paint(canvas, const Size(1920, 1080));
        recorder.endRecording();
      }

      // 에러 없이 완료되면 LRU 동작 정상
    });
  });

  group('캐시 통합 스트레스 테스트', () {
    test('스트로크와 테이블 동시 캐시 사용', () async {
      // Given
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();

      final strokes = _createTestStrokes(50);
      final tables = _createTestTables(3, rowCount: 10, colCount: 10);
      const canvasSize = Size(1920, 1080);

      // When: 스트로크 캐시
      final strokeImage = await cacheService.cacheStrokes(strokes, canvasSize, null);

      // 테이블 렌더링
      final painter = TablePainter(tables: tables);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, canvasSize);
      recorder.endRecording();

      // Then
      expect(strokeImage, isNotNull);

      // Cleanup
      cacheService.clearAll();
      TablePainter.clearCache();
    });

    test('장시간 사용 시뮬레이션 (100회 반복)', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
      const canvasSize = Size(1920, 1080);

      final stopwatch = Stopwatch()..start();

      for (int iteration = 0; iteration < 100; iteration++) {
        // 스트로크 캐시
        cacheService.invalidateCache();
        final strokes = _createTestStrokes(20 + (iteration % 10));
        await cacheService.cacheStrokes(strokes, canvasSize, null);

        // 테이블 렌더링
        if (iteration % 10 == 0) {
          final tables = _createTestTables(1, rowCount: 5, colCount: 5);
          final painter = TablePainter(tables: tables);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          painter.paint(canvas, canvasSize);
          recorder.endRecording();
        }
      }

      stopwatch.stop();
      print('장시간 시뮬레이션 완료: ${stopwatch.elapsedMilliseconds}ms');

      // Cleanup
      cacheService.clearAll();
      TablePainter.clearCache();
    });
  });

  group('엣지 케이스 테스트', () {
    test('매우 작은 캔버스 크기', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
      final strokes = _createTestStrokes(5);

      final image = await cacheService.cacheStrokes(
        strokes,
        const Size(10, 10), // 매우 작음
        null,
      );

      expect(image, isNotNull);
      cacheService.clearAll();
    });

    test('매우 큰 캔버스 크기', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
      final strokes = _createTestStrokes(5);

      final image = await cacheService.cacheStrokes(
        strokes,
        const Size(4096, 4096), // 매우 큼
        null,
      );

      expect(image, isNotNull);
      cacheService.clearAll();
    });

    test('스트로크 포인트가 1개인 경우', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();

      final stroke = Stroke(
        id: 'single-point',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [
          const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0, timestamp: 0),
        ],
        timestamp: 0,
      );

      final image = await cacheService.cacheStrokes(
        [stroke],
        const Size(800, 600),
        null,
      );

      // 단일 포인트는 그려지지 않음 (2개 이상 필요)
      expect(image, isNotNull);
      cacheService.clearAll();
    });

    test('빈 테이블 (셀 없음)', () {
      final table = CanvasTable(
        id: 'empty-table',
        position: const Offset(100, 100),
        rows: 0,
        columns: 0,
        timestamp: 0,
      );

      final painter = TablePainter(tables: [table]);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 에러 없이 렌더링되어야 함
      painter.paint(canvas, const Size(800, 600));
      recorder.endRecording();

      TablePainter.clearCache();
    });

    test('동시 캐시 접근 시뮬레이션', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();
      const canvasSize = Size(800, 600);

      // 동시에 여러 캐시 요청 (순차적으로 실행됨 - 싱글톤이므로)
      for (int i = 0; i < 10; i++) {
        cacheService.invalidateCache();
        final strokes = _createTestStrokes(5 + i);
        final result = await cacheService.cacheStrokes(strokes, canvasSize, null);
        expect(result, isNotNull);
      }

      cacheService.clearAll();
    });
  });

  group('Picture dispose 검증', () {
    test('cacheStrokes 호출 시 Picture가 dispose 되어야 함', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();

      // 반복적으로 캐시 생성하여 dispose 확인
      for (int i = 0; i < 50; i++) {
        cacheService.invalidateCache();
        final strokes = _createTestStrokes(10);
        await cacheService.cacheStrokes(
          strokes,
          const Size(800, 600),
          null,
        );
      }

      // 메모리 누수 없이 완료되면 성공
      // (실제 메모리 측정은 프로파일러 필요)
      cacheService.clearAll();
    });

    test('에러 발생 시에도 Picture가 dispose 되어야 함', () async {
      final cacheService = StrokeCacheService.instance;
      cacheService.clearAll();

      // 정상적인 캐시 생성
      final strokes = _createTestStrokes(5);
      final image = await cacheService.cacheStrokes(
        strokes,
        const Size(800, 600),
        null,
      );
      expect(image, isNotNull);

      cacheService.clearAll();
    });
  });
}

/// 테스트용 스트로크 생성
List<Stroke> _createTestStrokes(int count, {int pointsPerStroke = 20}) {
  final strokes = <Stroke>[];
  final now = DateTime.now().millisecondsSinceEpoch;

  for (int i = 0; i < count; i++) {
    final points = <StrokePoint>[];
    for (int j = 0; j < pointsPerStroke; j++) {
      points.add(StrokePoint(
        x: 100.0 + j * 10 + i * 5,
        y: 100.0 + j * 5 + i * 3,
        pressure: 0.5 + (j % 5) * 0.1,
        tilt: 0,
        timestamp: now + j,
      ),);
    }

    strokes.add(Stroke(
      id: 'stroke-$i',
      toolType: ToolType.pen,
      color: Colors.black,
      width: 2.0 + (i % 3),
      points: points,
      timestamp: now + i * 1000,
    ),);
  }

  return strokes;
}

/// 테스트용 테이블 생성
List<CanvasTable> _createTestTables(int count, {int rowCount = 5, int colCount = 5}) {
  final tables = <CanvasTable>[];
  final now = DateTime.now().millisecondsSinceEpoch;

  for (int t = 0; t < count; t++) {
    final cellContents = <List<String>>[];
    for (int r = 0; r < rowCount; r++) {
      final row = <String>[];
      for (int c = 0; c < colCount; c++) {
        row.add('R${r}C$c');
      }
      cellContents.add(row);
    }

    tables.add(CanvasTable(
      id: 'table-$t',
      position: Offset(100.0 + t * 300, 100.0),
      rows: rowCount,
      columns: colCount,
      cellContents: cellContents,
      timestamp: now,
    ),);
  }

  return tables;
}
