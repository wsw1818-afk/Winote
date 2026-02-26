import 'package:flutter_test/flutter_test.dart';

void main() {
  group('3손가락 제스처 로직 테스트', () {
    const tapMaxDuration = 300; // ms
    const tapMaxMovement = 30.0; // pixels

    test('탭 지속시간 300ms 이내면 탭으로 인식', () {
      const startTime = 1000;
      const endTime = 1200; // 200ms
      const duration = endTime - startTime;

      expect(duration < tapMaxDuration, isTrue);
    });

    test('탭 지속시간 300ms 초과면 탭 아님', () {
      const startTime = 1000;
      const endTime = 1400; // 400ms
      const duration = endTime - startTime;

      expect(duration < tapMaxDuration, isFalse);
    });

    test('손가락 이동 30px 이내면 탭', () {
      const pos1Start = Offset(100, 100);
      const pos1End = Offset(115, 110);

      final move = (pos1End - pos1Start).distance;
      expect(move < tapMaxMovement, isTrue);
    });

    test('손가락 이동 30px 초과면 탭 아님', () {
      const pos1Start = Offset(100, 100);
      const pos1End = Offset(140, 140);

      final move = (pos1End - pos1Start).distance;
      expect(move > tapMaxMovement, isTrue);
    });

    test('3손가락 스와이프 거리 계산', () {
      const startFocal = Offset(200, 300);
      const endFocal = Offset(350, 310);

      final swipeDelta = endFocal.dx - startFocal.dx;

      expect(swipeDelta, equals(150));
      expect(swipeDelta > 100, isTrue); // 스와이프 인식 임계값
    });

    test('스와이프 방향 결정 (좌=Undo)', () {
      const startFocal = Offset(300, 300);
      const endFocal = Offset(150, 310);

      final swipeDelta = endFocal.dx - startFocal.dx;

      expect(swipeDelta < 0, isTrue);
      expect(swipeDelta.abs() > 100, isTrue);
      // swipeDelta < 0 && abs > 100 → Undo
    });

    test('스와이프 방향 결정 (우=Redo)', () {
      const startFocal = Offset(150, 300);
      const endFocal = Offset(300, 310);

      final swipeDelta = endFocal.dx - startFocal.dx;

      expect(swipeDelta > 0, isTrue);
      expect(swipeDelta.abs() > 100, isTrue);
      // swipeDelta > 0 && abs > 100 → Redo
    });
  });

  group('2손가락 제스처 로직 테스트', () {
    test('핀치 줌 스케일 계산', () {
      const baseSpan = 100.0;
      const currentSpan = 200.0;
      const baseScale = 1.0;

      const rawScaleFactor = currentSpan / baseSpan;
      final newScale = (baseScale * rawScaleFactor).clamp(1.0, 3.0);

      expect(newScale, equals(2.0));
    });

    test('핀치 줌 스케일 클램핑 (최소)', () {
      const baseSpan = 200.0;
      const currentSpan = 50.0;
      const baseScale = 1.0;

      const rawScaleFactor = currentSpan / baseSpan;
      final newScale = (baseScale * rawScaleFactor).clamp(1.0, 3.0);

      expect(newScale, equals(1.0)); // 최소값으로 클램프
    });

    test('핀치 줌 스케일 클램핑 (최대)', () {
      const baseSpan = 50.0;
      const currentSpan = 200.0;
      const baseScale = 2.0;

      const rawScaleFactor = currentSpan / baseSpan;
      final newScale = (baseScale * rawScaleFactor).clamp(1.0, 3.0);

      expect(newScale, equals(3.0)); // 최대값으로 클램프
    });

    test('2손가락 탭 후 Undo 조건', () {
      const tapDuration = 200; // ms
      const moved = false;
      const tapMaxDuration = 300;

      const shouldUndo = tapDuration < tapMaxDuration && !moved;
      expect(shouldUndo, isTrue);
    });
  });

  group('포커스 포인트 계산 테스트', () {
    test('2점의 focal point', () {
      const p1 = Offset(100, 100);
      const p2 = Offset(200, 200);

      final focal = Offset(
        (p1.dx + p2.dx) / 2,
        (p1.dy + p2.dy) / 2,
      );

      expect(focal, equals(const Offset(150, 150)));
    });

    test('3점의 focal point', () {
      const p1 = Offset(100, 100);
      const p2 = Offset(200, 100);
      const p3 = Offset(150, 200);

      final focal = Offset(
        (p1.dx + p2.dx + p3.dx) / 3,
        (p1.dy + p2.dy + p3.dy) / 3,
      );

      expect(focal.dx, closeTo(150, 0.01));
      expect(focal.dy, closeTo(133.33, 0.01));
    });

    test('2점 간 거리 (span) 계산', () {
      const p1 = Offset(100, 100);
      const p2 = Offset(200, 100);

      final span = (p2 - p1).distance;

      expect(span, equals(100));
    });
  });
}
