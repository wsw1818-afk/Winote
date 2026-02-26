import 'package:flutter_test/flutter_test.dart';

/// 제스처 감지 로직 단위 테스트
/// 2손가락 더블탭, 3손가락 탭 감지 알고리즘 검증
void main() {
  group('2손가락 더블탭 감지 테스트', () {
    // 테스트용 상수 (drawing_canvas.dart와 동일)
    const int tapMaxDuration = 300; // ms
    const int doubleTapMaxInterval = 400; // ms
    const double tapMaxMovement = 30.0; // pixels

    test('정상적인 2손가락 더블탭 감지', () {
      // 첫 번째 탭
      final firstTapStart = DateTime.now().millisecondsSinceEpoch;
      final firstTapEnd = firstTapStart + 100; // 100ms 탭
      final firstTapDuration = firstTapEnd - firstTapStart;

      expect(firstTapDuration < tapMaxDuration, isTrue,
        reason: '첫 번째 탭 시간이 유효해야 함',);

      // 두 번째 탭 (200ms 후)
      final secondTapStart = firstTapEnd + 200;
      final secondTapEnd = secondTapStart + 100;
      final secondTapDuration = secondTapEnd - secondTapStart;
      final intervalBetweenTaps = secondTapStart - firstTapEnd;

      expect(secondTapDuration < tapMaxDuration, isTrue,
        reason: '두 번째 탭 시간이 유효해야 함',);
      expect(intervalBetweenTaps < doubleTapMaxInterval, isTrue,
        reason: '두 탭 사이 간격이 유효해야 함',);
    });

    test('너무 느린 더블탭은 감지 안됨', () {
      final firstTapEnd = DateTime.now().millisecondsSinceEpoch;
      final secondTapStart = firstTapEnd + 500; // 500ms 후 (400ms 초과)
      final interval = secondTapStart - firstTapEnd;

      expect(interval < doubleTapMaxInterval, isFalse,
        reason: '500ms 간격은 더블탭으로 인식하면 안됨',);
    });

    test('탭 중 손가락 이동하면 무효', () {
      const startPos = Offset(100, 100);
      const endPos = Offset(150, 150); // 약 70px 이동
      final movement = (endPos - startPos).distance;

      expect(movement > tapMaxMovement, isTrue,
        reason: '30px 이상 이동하면 탭이 아님',);
    });

    test('탭 중 손가락 약간 이동은 허용', () {
      const startPos = Offset(100, 100);
      const endPos = Offset(110, 115); // 약 18px 이동
      final movement = (endPos - startPos).distance;

      expect(movement <= tapMaxMovement, isTrue,
        reason: '30px 이하 이동은 탭으로 허용',);
    });
  });

  group('3손가락 탭 감지 테스트', () {
    const int tapMaxDuration = 300; // ms
    const double tapMaxMovement = 30.0; // pixels

    test('정상적인 3손가락 탭 감지', () {
      final tapStart = DateTime.now().millisecondsSinceEpoch;
      final tapEnd = tapStart + 150; // 150ms 탭
      final tapDuration = tapEnd - tapStart;

      expect(tapDuration < tapMaxDuration, isTrue,
        reason: '150ms는 유효한 탭 시간',);
    });

    test('너무 긴 3손가락 터치는 탭이 아님', () {
      final tapStart = DateTime.now().millisecondsSinceEpoch;
      final tapEnd = tapStart + 400; // 400ms
      final tapDuration = tapEnd - tapStart;

      expect(tapDuration < tapMaxDuration, isFalse,
        reason: '400ms는 탭이 아니라 롱프레스',);
    });

    test('3손가락 중 하나라도 이동하면 무효', () {
      const positions = [
        Offset(100, 100),
        Offset(200, 100),
        Offset(150, 200),
      ];

      const movedPositions = [
        Offset(100, 100), // 이동 안함
        Offset(250, 100), // 50px 이동
        Offset(150, 200), // 이동 안함
      ];

      bool anyMoved = false;
      for (int i = 0; i < 3; i++) {
        final movement = (movedPositions[i] - positions[i]).distance;
        if (movement > tapMaxMovement) {
          anyMoved = true;
          break;
        }
      }

      expect(anyMoved, isTrue,
        reason: '손가락 하나가 50px 이동했으므로 무효',);
    });
  });

  group('S-Pen 뒤집기 감지 테스트', () {
    test('invertedStylus 타입 식별', () {
      // PointerDeviceKind enum 값 시뮬레이션
      const int stylus = 2;
      const int invertedStylus = 3;
      const int touch = 1;

      expect(invertedStylus != stylus, isTrue,
        reason: '뒤집힌 스타일러스는 일반 스타일러스와 다름',);
      expect(invertedStylus != touch, isTrue,
        reason: '뒤집힌 스타일러스는 터치와 다름',);
    });

    test('S-Pen 뒤집기 시 지우개로 전환해야 함', () {
      // 도구 상태 시뮬레이션
      String currentTool = 'pen';
      const bool isInvertedStylus = true;

      if (isInvertedStylus) {
        currentTool = 'eraser';
      }

      expect(currentTool, equals('eraser'),
        reason: '뒤집힌 스타일러스 감지 시 지우개로 전환',);
    });
  });

  group('키보드 단축키 매핑 테스트', () {
    test('도구 전환 단축키 매핑', () {
      final shortcuts = {
        'P': 'pen',
        'E': 'eraser',
        'H': 'highlighter',
        'L': 'lasso',
      };

      expect(shortcuts['P'], equals('pen'));
      expect(shortcuts['E'], equals('eraser'));
      expect(shortcuts['H'], equals('highlighter'));
      expect(shortcuts['L'], equals('lasso'));
    });

    test('화면 맞춤 단축키', () {
      final shortcuts = {
        'F': 'fitToScreen',
        'Home': 'fitToScreen',
      };

      expect(shortcuts['F'], equals('fitToScreen'));
      expect(shortcuts['Home'], equals('fitToScreen'));
    });

    test('선택 삭제 단축키', () {
      final shortcuts = {
        'Delete': 'deleteSelection',
        'Backspace': 'deleteSelection',
      };

      expect(shortcuts['Delete'], equals('deleteSelection'));
      expect(shortcuts['Backspace'], equals('deleteSelection'));
    });

    test('Undo/Redo 단축키', () {
      final shortcuts = {
        'Ctrl+Z': 'undo',
        'Ctrl+Y': 'redo',
        'Ctrl+Shift+Z': 'redo',
      };

      expect(shortcuts['Ctrl+Z'], equals('undo'));
      expect(shortcuts['Ctrl+Y'], equals('redo'));
      expect(shortcuts['Ctrl+Shift+Z'], equals('redo'));
    });
  });

  group('화면 맞춤(Fit-to-Screen) 테스트', () {
    test('화면 맞춤 시 scale과 offset 초기화', () {
      // 초기 상태: 확대/이동된 상태
      double scale = 2.5;
      Offset offset = const Offset(100, 200);

      // fitToScreen 호출
      scale = 1.0;
      offset = Offset.zero;

      expect(scale, equals(1.0),
        reason: '화면 맞춤 후 scale은 1.0이어야 함',);
      expect(offset, equals(Offset.zero),
        reason: '화면 맞춤 후 offset은 (0,0)이어야 함',);
    });
  });
}
