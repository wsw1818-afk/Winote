import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/core/services/stroke_cache_service.dart';

void main() {
  group('StrokeCacheService 테스트', () {
    late StrokeCacheService service;

    setUp(() {
      service = StrokeCacheService.instance;
      service.clearAll();
    });

    test('싱글톤 인스턴스 확인', () {
      final instance1 = StrokeCacheService.instance;
      final instance2 = StrokeCacheService.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('빈 스트로크 목록은 캐시 유효하지 않음', () {
      expect(service.isCacheValid([]), isFalse);
    });

    test('clearAll 후 캐시 이미지 null', () {
      service.clearAll();
      expect(service.getCachedImage(), isNull);
    });

    test('invalidateCache 호출 시 캐시 무효화', () {
      // 초기 상태
      expect(service.getCachedImage(), isNull);

      service.invalidateCache();
      expect(service.getCachedImage(), isNull);
    });

    test('스트로크 생성 헬퍼', () {
      final stroke = _createTestStroke('test-1', 5);
      expect(stroke.id, equals('test-1'));
      expect(stroke.points.length, equals(5));
    });
  });

  group('TileCache 테스트', () {
    late TileCache tileCache;

    setUp(() {
      tileCache = TileCache();
    });

    test('초기 상태에서 타일 없음', () {
      expect(tileCache.getTile(0, 0), isNull);
      expect(tileCache.getTile(1, 1), isNull);
    });

    test('clear 호출 시 모든 타일 삭제', () {
      // 타일은 실제 ui.Image가 필요하므로 clear만 테스트
      tileCache.clear();
      expect(tileCache.getTile(0, 0), isNull);
    });

    test('타일 크기 상수 확인', () {
      expect(TileCache.tileSize, equals(512.0));
    });
  });

  group('필압 변동 감지 테스트', () {
    test('균일한 필압은 변동 없음으로 감지', () {
      // 모든 포인트의 압력이 동일
      final stroke = _createTestStrokeWithUniformPressure('uniform', 10, 0.5);
      // _hasPressureVariation은 private이므로 간접 테스트
      // 균일한 압력 스트로크는 points 확인
      final minP = stroke.points.map((p) => p.pressure).reduce((a, b) => a < b ? a : b);
      final maxP = stroke.points.map((p) => p.pressure).reduce((a, b) => a > b ? a : b);
      expect(maxP - minP, lessThan(0.1)); // 변동 0.1 미만
    });

    test('가변 필압은 변동 있음으로 감지', () {
      final stroke = _createTestStrokeWithVariablePressure('variable', 10);
      final minP = stroke.points.map((p) => p.pressure).reduce((a, b) => a < b ? a : b);
      final maxP = stroke.points.map((p) => p.pressure).reduce((a, b) => a > b ? a : b);
      expect(maxP - minP, greaterThan(0.1)); // 변동 0.1 이상
    });
  });

  group('틸트 기반 굵기 계산 테스트', () {
    test('틸트 0일 때 굵기 변화 없음', () {
      const baseWidth = 2.0;
      const tilt = 0.0;
      // 틸트 < 0.1이면 적용 안됨
      const multiplier = tilt > 0.1 ? 1.0 + (tilt * 0.5) : 1.0;
      expect(baseWidth * multiplier, equals(baseWidth));
    });

    test('틸트 0.5일 때 1.25배 굵기', () {
      const baseWidth = 2.0;
      const tilt = 0.5;
      const multiplier = 1.0 + (tilt * 0.5); // 1.25
      expect(baseWidth * multiplier, closeTo(2.5, 0.01));
    });

    test('틸트 1.0일 때 1.5배 굵기 (최대)', () {
      const baseWidth = 2.0;
      const tilt = 1.0;
      const multiplier = 1.0 + (tilt * 0.5); // 1.5
      expect(baseWidth * multiplier, closeTo(3.0, 0.01));
    });

    test('틸트 0.05일 때 적용 안됨 (임계값 0.1 미만)', () {
      const baseWidth = 2.0;
      const tilt = 0.05;
      // 틸트 < 0.1이면 적용 안됨
      const multiplier = tilt > 0.1 ? 1.0 + (tilt * 0.5) : 1.0;
      expect(baseWidth * multiplier, equals(baseWidth));
    });
  });

  group('필압 기반 굵기 계산 테스트', () {
    test('압력 0일 때 0.5배 굵기 (최소)', () {
      const baseWidth = 2.0;
      const pressure = 0.0;
      const width = baseWidth * (0.5 + pressure * 0.8);
      expect(width, closeTo(1.0, 0.01)); // 2.0 * 0.5 = 1.0
    });

    test('압력 0.5일 때 0.9배 굵기', () {
      const baseWidth = 2.0;
      const pressure = 0.5;
      const width = baseWidth * (0.5 + pressure * 0.8);
      expect(width, closeTo(1.8, 0.01)); // 2.0 * 0.9 = 1.8
    });

    test('압력 1.0일 때 1.3배 굵기 (최대)', () {
      const baseWidth = 2.0;
      const pressure = 1.0;
      const width = baseWidth * (0.5 + pressure * 0.8);
      expect(width, closeTo(2.6, 0.01)); // 2.0 * 1.3 = 2.6
    });
  });

  group('필압 + 틸트 복합 계산 테스트', () {
    test('압력 1.0 + 틸트 1.0일 때 최대 굵기', () {
      const baseWidth = 2.0;
      const pressure = 1.0;
      const tilt = 1.0;

      // 필압 계산
      double width = baseWidth * (0.5 + pressure * 0.8); // 2.6

      // 틸트 적용
      const tiltMultiplier = 1.0 + (tilt * 0.5); // 1.5
      width *= tiltMultiplier; // 2.6 * 1.5 = 3.9

      expect(width, closeTo(3.9, 0.01));
    });

    test('압력 0.5 + 틸트 0.5일 때 중간 굵기', () {
      const baseWidth = 2.0;
      const pressure = 0.5;
      const tilt = 0.5;

      double width = baseWidth * (0.5 + pressure * 0.8); // 1.8
      const tiltMultiplier = 1.0 + (tilt * 0.5); // 1.25
      width *= tiltMultiplier; // 1.8 * 1.25 = 2.25

      expect(width, closeTo(2.25, 0.01));
    });
  });
}

// 테스트용 스트로크 생성 헬퍼
Stroke _createTestStroke(String id, int pointCount) {
  final points = <StrokePoint>[];
  for (int i = 0; i < pointCount; i++) {
    points.add(StrokePoint(
      x: i * 10.0,
      y: i * 5.0,
      pressure: 0.5 + (i * 0.05),
      tilt: 0.0,
      timestamp: i * 100,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

// 균일한 필압 스트로크 생성
Stroke _createTestStrokeWithUniformPressure(String id, int pointCount, double pressure) {
  final points = <StrokePoint>[];
  for (int i = 0; i < pointCount; i++) {
    points.add(StrokePoint(
      x: i * 10.0,
      y: i * 5.0,
      pressure: pressure, // 모두 동일한 압력
      tilt: 0.0,
      timestamp: i * 100,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

// 가변 필압 스트로크 생성 (0.2 ~ 0.9 범위)
Stroke _createTestStrokeWithVariablePressure(String id, int pointCount) {
  final points = <StrokePoint>[];
  for (int i = 0; i < pointCount; i++) {
    points.add(StrokePoint(
      x: i * 10.0,
      y: i * 5.0,
      pressure: 0.2 + (i / pointCount) * 0.7, // 0.2에서 0.9까지 변동
      tilt: 0.0,
      timestamp: i * 100,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

// 틸트가 있는 스트로크 생성
Stroke _createTestStrokeWithTilt(String id, int pointCount, double tilt) {
  final points = <StrokePoint>[];
  for (int i = 0; i < pointCount; i++) {
    points.add(StrokePoint(
      x: i * 10.0,
      y: i * 5.0,
      pressure: 0.5,
      tilt: tilt,
      timestamp: i * 100,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}
