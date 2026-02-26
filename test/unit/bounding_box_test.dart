import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/domain/entities/bounding_box.dart';

void main() {
  group('BoundingBox 테스트', () {
    test('fromPoint로 생성', () {
      final bbox = BoundingBox.fromPoint(100, 200);
      expect(bbox.minX, equals(100));
      expect(bbox.maxX, equals(100));
      expect(bbox.minY, equals(200));
      expect(bbox.maxY, equals(200));
    });

    test('empty로 생성', () {
      final bbox = BoundingBox.empty();
      expect(bbox.minX, equals(double.infinity));
      expect(bbox.maxX, equals(double.negativeInfinity));
    });

    test('expand로 확장', () {
      final bbox = BoundingBox.fromPoint(50, 50);
      bbox.expand(100, 150);
      bbox.expand(0, 25);

      expect(bbox.minX, equals(0));
      expect(bbox.maxX, equals(100));
      expect(bbox.minY, equals(25));
      expect(bbox.maxY, equals(150));
    });

    test('width/height 계산', () {
      final bbox = BoundingBox.fromPoint(10, 20);
      bbox.expand(110, 70);

      expect(bbox.width, equals(100));
      expect(bbox.height, equals(50));
    });

    test('center 계산', () {
      final bbox = BoundingBox.fromPoint(0, 0);
      bbox.expand(100, 100);

      // center는 Offset 타입
      expect(bbox.center.dx, equals(50));
      expect(bbox.center.dy, equals(50));
    });

    test('contains 포인트 체크', () {
      final bbox = BoundingBox.fromPoint(0, 0);
      bbox.expand(100, 100);

      expect(bbox.contains(50, 50), isTrue);
      expect(bbox.contains(0, 0), isTrue);
      expect(bbox.contains(100, 100), isTrue);
      expect(bbox.contains(-1, 50), isFalse);
      expect(bbox.contains(101, 50), isFalse);
    });

    test('overlaps Rect와 교차 확인', () {
      final bbox = BoundingBox.fromPoint(0, 0);
      bbox.expand(100, 100);

      // overlaps는 Rect 타입을 받음
      expect(bbox.overlaps(const Rect.fromLTRB(50, 50, 150, 150)), isTrue);
      expect(bbox.overlaps(const Rect.fromLTRB(200, 200, 300, 300)), isFalse);
    });

    test('merge로 다른 BoundingBox와 병합', () {
      final bbox1 = BoundingBox.fromPoint(0, 0);
      bbox1.expand(50, 50);

      final bbox2 = BoundingBox.fromPoint(30, 30);
      bbox2.expand(100, 100);

      bbox1.merge(bbox2);

      expect(bbox1.minX, equals(0));
      expect(bbox1.minY, equals(0));
      expect(bbox1.maxX, equals(100));
      expect(bbox1.maxY, equals(100));
    });

    test('copy로 복사', () {
      final original = BoundingBox.fromPoint(10, 20);
      original.expand(30, 40);

      final copied = original.copy();

      expect(copied.minX, equals(original.minX));
      expect(copied.maxX, equals(original.maxX));
      expect(copied.minY, equals(original.minY));
      expect(copied.maxY, equals(original.maxY));

      // 복사본 수정이 원본에 영향 없음
      copied.expand(100, 100);
      expect(original.maxX, equals(30));
      expect(copied.maxX, equals(100));
    });

    test('toRect 변환', () {
      final bbox = BoundingBox.fromPoint(10, 20);
      bbox.expand(110, 120);

      final rect = bbox.toRect();

      expect(rect.left, equals(10));
      expect(rect.top, equals(20));
      expect(rect.width, equals(100));
      expect(rect.height, equals(100));
    });
  });
}
