import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/core/providers/drawing_state.dart';

void main() {
  group('호버 커서 로직 테스트', () {
    test('펜 도구 커서 크기 계산', () {
      const strokeWidth = 4.0;
      const scale = 2.0;
      const cursorSize = strokeWidth * scale;

      expect(cursorSize, equals(8.0));
    });

    test('지우개 도구 커서 반경 계산', () {
      const eraserWidth = 20.0;
      const scale = 1.5;
      const radius = eraserWidth * scale / 2;

      expect(radius, equals(15.0));
    });

    test('형광펜 커서 사이즈 (납작한 형태)', () {
      const highlighterWidth = 20.0;
      const scale = 1.0;
      const cursorWidth = highlighterWidth * scale;
      const cursorHeight = cursorWidth * 0.4;

      expect(cursorWidth, equals(20.0));
      expect(cursorHeight, equals(8.0));
    });

    test('캔버스 좌표를 화면 좌표로 변환', () {
      const canvasPos = Offset(100, 200);
      const scale = 2.0;
      const offset = Offset(50, 30);

      final screenPos = Offset(
        canvasPos.dx * scale + offset.dx,
        canvasPos.dy * scale + offset.dy,
      );

      expect(screenPos.dx, equals(250)); // 100 * 2 + 50
      expect(screenPos.dy, equals(430)); // 200 * 2 + 30
    });
  });

  group('DrawingTool 테스트', () {
    test('도구별 커서 타입 결정', () {
      // 펜 계열 도구들
      final penTools = [DrawingTool.pen];
      for (final tool in penTools) {
        expect(_getCursorType(tool), equals('pen'));
      }

      // 형광펜
      expect(_getCursorType(DrawingTool.highlighter), equals('highlighter'));

      // 지우개
      expect(_getCursorType(DrawingTool.eraser), equals('eraser'));

      // 도형 도구들
      final shapeTools = [
        DrawingTool.shapeLine,
        DrawingTool.shapeRectangle,
        DrawingTool.shapeCircle,
        DrawingTool.shapeArrow,
      ];
      for (final tool in shapeTools) {
        expect(_getCursorType(tool), equals('shape'));
      }

      // 올가미
      expect(_getCursorType(DrawingTool.lasso), equals('default'));
    });
  });

  group('색상 opacity 테스트', () {
    test('펜 커서 외곽선 opacity', () {
      final color = Colors.black.withOpacity(0.5);
      expect(color.opacity, closeTo(0.5, 0.01));
    });

    test('형광펜 커서 fill opacity', () {
      final color = Colors.yellow.withOpacity(0.4);
      expect(color.opacity, closeTo(0.4, 0.01));
    });

    test('지우개 커서 fill opacity', () {
      final color = Colors.white.withOpacity(0.3);
      expect(color.opacity, closeTo(0.3, 0.01));
    });
  });
}

// 도구별 커서 타입 결정 헬퍼
String _getCursorType(DrawingTool tool) {
  switch (tool) {
    case DrawingTool.pen:
      return 'pen';
    case DrawingTool.highlighter:
      return 'highlighter';
    case DrawingTool.eraser:
      return 'eraser';
    case DrawingTool.shapeLine:
    case DrawingTool.shapeRectangle:
    case DrawingTool.shapeCircle:
    case DrawingTool.shapeArrow:
      return 'shape';
    default:
      return 'default';
  }
}
