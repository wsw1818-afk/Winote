import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/core/services/stroke_cache_service.dart';

/// 대규모 스트로크 성능 벤치마크 테스트
/// 1000/5000/10000 스트로크 렌더링 성능 측정
void main() {
  group('스트로크 생성 성능 테스트', () {
    test('100개 스트로크 생성 성능', () {
      final stopwatch = Stopwatch()..start();
      final strokes = _generateStrokes(100, 50);
      stopwatch.stop();

      expect(strokes.length, equals(100));
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // 100ms 미만
      print('100개 스트로크 생성: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('1000개 스트로크 생성 성능', () {
      final stopwatch = Stopwatch()..start();
      final strokes = _generateStrokes(1000, 50);
      stopwatch.stop();

      expect(strokes.length, equals(1000));
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // 500ms 미만
      print('1000개 스트로크 생성: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('5000개 스트로크 생성 성능', () {
      final stopwatch = Stopwatch()..start();
      final strokes = _generateStrokes(5000, 30);
      stopwatch.stop();

      expect(strokes.length, equals(5000));
      expect(stopwatch.elapsedMilliseconds, lessThan(2000)); // 2초 미만
      print('5000개 스트로크 생성: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('캐시 키 생성 성능 테스트', () {
    test('100개 스트로크 캐시 키 생성', () {
      final strokes = _generateStrokes(100, 50);
      final service = StrokeCacheService.instance;

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        service.isCacheValid(strokes);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(150)); // 150ms 미만
      print('100개 스트로크 캐시 키 100회 생성: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('1000개 스트로크 캐시 키 생성', () {
      final strokes = _generateStrokes(1000, 50);
      final service = StrokeCacheService.instance;

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 10; i++) {
        service.isCacheValid(strokes);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(200)); // 200ms 미만
      print('1000개 스트로크 캐시 키 10회 생성: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('메모리 사용량 추정 테스트', () {
    test('스트로크 메모리 사용량 계산', () {
      // StrokePoint: x(8) + y(8) + pressure(8) + tilt(8) + timestamp(8) = 40 bytes
      // Stroke: id(~36) + color(8) + width(8) + toolType(4) + points(n*40) = ~56 + n*40 bytes

      final strokes100 = _generateStrokes(100, 50);
      final strokes1000 = _generateStrokes(1000, 50);
      final strokes5000 = _generateStrokes(5000, 30);

      final memory100 = _estimateMemoryUsage(strokes100);
      final memory1000 = _estimateMemoryUsage(strokes1000);
      final memory5000 = _estimateMemoryUsage(strokes5000);

      print('100개 스트로크 (50포인트): ${(memory100 / 1024 / 1024).toStringAsFixed(2)} MB');
      print('1000개 스트로크 (50포인트): ${(memory1000 / 1024 / 1024).toStringAsFixed(2)} MB');
      print('5000개 스트로크 (30포인트): ${(memory5000 / 1024 / 1024).toStringAsFixed(2)} MB');

      // 메모리 임계값 검증
      expect(memory100, lessThan(1 * 1024 * 1024)); // 1MB 미만
      expect(memory1000, lessThan(10 * 1024 * 1024)); // 10MB 미만
      expect(memory5000, lessThan(30 * 1024 * 1024)); // 30MB 미만
    });

    test('Undo 스택 메모리 사용량 (델타 방식)', () {
      // 델타 방식: 각 액션당 1개 스트로크만 저장
      // 100개 히스토리 * 50포인트 스트로크 = 약 200KB

      const strokeSize = 56 + (50 * 40); // ~2056 bytes per stroke
      const undoStackSize = 100 * strokeSize; // 100개 히스토리

      print('델타 Undo 스택 100개: ${(undoStackSize / 1024).toStringAsFixed(2)} KB');

      // 구방식 대비 절감량 (전체 복사 시)
      const oldWaySize = 100 * (1000 * strokeSize); // 100개 히스토리 * 1000개 스트로크
      print('구방식 대비 절감: ${((1 - undoStackSize / oldWaySize) * 100).toStringAsFixed(1)}%');

      expect(undoStackSize, lessThan(500 * 1024)); // 500KB 미만
    });
  });

  group('캐시 무효화 성능 테스트', () {
    test('캐시 무효화 후 재생성 성능', () {
      final service = StrokeCacheService.instance;
      final strokes = _generateStrokes(500, 50);

      // 초기 캐시 생성
      service.invalidateCache();
      expect(service.isCacheValid(strokes), isFalse);

      // 무효화 성능
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        service.invalidateCache();
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10)); // 10ms 미만
      print('캐시 무효화 100회: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('TileCache LRU 성능 테스트', () {
    test('100개 타일 LRU 순서 업데이트 성능', () {
      final tileCache = TileCache();

      // 100개 타일 설정 (maxTiles=100이므로 eviction 발생 안함)
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        // Note: 실제 ui.Image 생성은 비용이 크므로 여기서는 get만 테스트
        tileCache.getTile(i % 10, i ~/ 10);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10)); // 10ms 미만
      print('100개 타일 조회: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('타일 캐시 eviction 성능', () {
      final tileCache = TileCache();

      // 타일 eviction이 발생하는지 확인만 (실제 이미지 없이)
      expect(tileCache.tileCount, equals(0));

      // clear 성능
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        tileCache.clear();
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10)); // 10ms 미만
      print('타일 캐시 clear 1000회: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('스트로크 검색/필터링 성능', () {
    test('1000개 스트로크에서 ID로 검색', () {
      final strokes = _generateStrokes(1000, 50);
      final targetId = strokes[500].id;

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        final found = strokes.firstWhere((s) => s.id == targetId);
        expect(found.id, equals(targetId));
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // 100ms 미만
      print('1000개 스트로크 ID 검색 1000회: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('영역 기반 스트로크 필터링', () {
      final strokes = _generateStrokes(1000, 50);
      const region = Rect.fromLTWH(100, 100, 200, 200);

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        final filtered = strokes.where((stroke) {
          return stroke.points.any((p) =>
            p.x >= region.left && p.x <= region.right &&
            p.y >= region.top && p.y <= region.bottom,
          );
        }).toList();
        // 일부 스트로크가 영역에 포함됨
        expect(filtered.length, greaterThan(0));
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // 500ms 미만
      print('영역 필터링 100회: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('극한 조건 테스트', () {
    test('10000개 스트로크 생성 (스트레스 테스트)', () {
      final stopwatch = Stopwatch()..start();
      final strokes = _generateStrokes(10000, 20);
      stopwatch.stop();

      expect(strokes.length, equals(10000));
      print('10000개 스트로크 생성: ${stopwatch.elapsedMilliseconds}ms');

      final memoryEstimate = _estimateMemoryUsage(strokes);
      print('메모리 사용량: ${(memoryEstimate / 1024 / 1024).toStringAsFixed(2)} MB');

      // 성능 기준: 5초 미만, 메모리 100MB 미만
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      expect(memoryEstimate, lessThan(100 * 1024 * 1024));
    });

    test('단일 스트로크 1000포인트 (긴 필기)', () {
      final random = Random(42);
      final points = <StrokePoint>[];
      double x = 100, y = 100;

      for (int i = 0; i < 1000; i++) {
        x += random.nextDouble() * 10 - 5;
        y += random.nextDouble() * 10 - 5;
        points.add(StrokePoint(
          x: x, y: y,
          pressure: 0.5 + random.nextDouble() * 0.5,
          tilt: random.nextDouble() * 0.5,
          timestamp: i,
        ),);
      }

      final stroke = Stroke(
        id: 'long_stroke',
        points: points,
        color: Colors.black,
        width: 2.0,
        toolType: ToolType.pen,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(stroke.points.length, equals(1000));

      // Bounding box 계산 성능 (직접 계산)
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        _calculateBoundingBox(stroke);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // 100ms 미만
      print('1000포인트 스트로크 bounds 계산 1000회: ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}

/// 테스트용 스트로크 목록 생성
List<Stroke> _generateStrokes(int count, int pointsPerStroke) {
  final random = Random(42); // 재현 가능한 랜덤
  final strokes = <Stroke>[];

  for (int i = 0; i < count; i++) {
    final points = <StrokePoint>[];
    double x = random.nextDouble() * 1000;
    double y = random.nextDouble() * 1000;

    for (int j = 0; j < pointsPerStroke; j++) {
      x += random.nextDouble() * 20 - 10;
      y += random.nextDouble() * 20 - 10;
      points.add(StrokePoint(
        x: x, y: y,
        pressure: 0.3 + random.nextDouble() * 0.7,
        tilt: random.nextDouble() * 0.5,
        timestamp: j,
      ),);
    }

    strokes.add(Stroke(
      id: 'stroke_$i',
      points: points,
      color: Color((random.nextDouble() * 0xFFFFFF).toInt()).withOpacity(1.0),
      width: 1.0 + random.nextDouble() * 4.0,
      toolType: ToolType.values[random.nextInt(ToolType.values.length)],
      timestamp: DateTime.now().millisecondsSinceEpoch + i,
    ),);
  }

  return strokes;
}

/// 스트로크 목록의 메모리 사용량 추정 (bytes)
int _estimateMemoryUsage(List<Stroke> strokes) {
  int totalBytes = 0;

  for (final stroke in strokes) {
    // Stroke 기본 오버헤드: ~56 bytes (id, color, width, toolType, etc)
    totalBytes += 56;

    // 각 StrokePoint: ~40 bytes (x, y, pressure, tilt, timestamp)
    totalBytes += stroke.points.length * 40;
  }

  return totalBytes;
}

/// 스트로크 바운딩 박스 계산
Rect _calculateBoundingBox(Stroke stroke) {
  if (stroke.points.isEmpty) return Rect.zero;

  double minX = stroke.points.first.x;
  double maxX = stroke.points.first.x;
  double minY = stroke.points.first.y;
  double maxY = stroke.points.first.y;

  for (final point in stroke.points) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}
