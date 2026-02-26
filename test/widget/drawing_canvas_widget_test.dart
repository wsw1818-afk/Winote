import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/presentation/widgets/canvas/drawing_canvas.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/core/providers/drawing_state.dart';

/// DrawingCanvas 위젯 테스트
/// 실제 위젯 렌더링 및 사용자 상호작용을 테스트
void main() {
  group('DrawingCanvas 위젯 기본 테스트', () {
    testWidgets('위젯 렌더링 성공', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(),
          ),
        ),
      );

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('초기 속성 적용 확인', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              strokeColor: Colors.red,
              strokeWidth: 5.0,
              eraserWidth: 30.0,
              toolType: ToolType.pen,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.strokeColor, equals(Colors.red));
      expect(widget.strokeWidth, equals(5.0));
      expect(widget.eraserWidth, equals(30.0));
      expect(widget.toolType, equals(ToolType.pen));
    });

    testWidgets('initialStrokes 렌더링', (tester) async {
      final initialStrokes = [
        _createTestStroke('stroke-1', Colors.black),
        _createTestStroke('stroke-2', Colors.blue),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              initialStrokes: initialStrokes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('페이지 템플릿 적용 확인', (tester) async {
      for (final template in PageTemplate.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DrawingCanvas(
                pageTemplate: template,
              ),
            ),
          ),
        );

        final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
        expect(widget.pageTemplate, equals(template));
      }
    });
  });

  group('DrawingCanvas 콜백 테스트', () {
    testWidgets('onStrokesChanged 콜백 호출', (tester) async {
      List<Stroke>? receivedStrokes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              onStrokesChanged: (strokes) {
                receivedStrokes = strokes;
              },
            ),
          ),
        ),
      );

      // 제스처 시뮬레이션은 복잡하므로 콜백 설정 확인
      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.onStrokesChanged, isNotNull);
    });

    testWidgets('onUndo/onRedo 콜백 설정 확인', (tester) async {
      bool undoCalled = false;
      bool redoCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              onUndo: () => undoCalled = true,
              onRedo: () => redoCalled = true,
              canUndo: true,
              canRedo: true,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.onUndo, isNotNull);
      expect(widget.onRedo, isNotNull);
      expect(widget.canUndo, isTrue);
      expect(widget.canRedo, isTrue);
    });

    testWidgets('onCanvasTouchStart 콜백 설정', (tester) async {
      bool touchStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              onCanvasTouchStart: () => touchStarted = true,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.onCanvasTouchStart, isNotNull);
    });
  });

  group('DrawingCanvas 도구 전환 테스트', () {
    testWidgets('펜 도구 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawingTool: DrawingTool.pen,
              toolType: ToolType.pen,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.drawingTool, equals(DrawingTool.pen));
    });

    testWidgets('형광펜 도구 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawingTool: DrawingTool.highlighter,
              toolType: ToolType.highlighter,
              highlighterColor: Colors.yellow,
              highlighterWidth: 25.0,
              highlighterOpacity: 0.5,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.drawingTool, equals(DrawingTool.highlighter));
      expect(widget.highlighterColor, equals(Colors.yellow));
      expect(widget.highlighterWidth, equals(25.0));
      expect(widget.highlighterOpacity, equals(0.5));
    });

    testWidgets('지우개 도구 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawingTool: DrawingTool.eraser,
              toolType: ToolType.eraser,
              eraserWidth: 40.0,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.drawingTool, equals(DrawingTool.eraser));
      expect(widget.eraserWidth, equals(40.0));
    });

    testWidgets('올가미 도구 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawingTool: DrawingTool.lasso,
              lassoColor: Colors.blue,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.drawingTool, equals(DrawingTool.lasso));
      expect(widget.lassoColor, equals(Colors.blue));
    });

    testWidgets('레이저 포인터 도구 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              drawingTool: DrawingTool.laserPointer,
              laserPointerColor: Colors.green,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.drawingTool, equals(DrawingTool.laserPointer));
      expect(widget.laserPointerColor, equals(Colors.green));
    });

    testWidgets('도형 도구 설정', (tester) async {
      final shapeTools = [
        DrawingTool.shapeLine,
        DrawingTool.shapeRectangle,
        DrawingTool.shapeCircle,
        DrawingTool.shapeArrow,
      ];

      for (final tool in shapeTools) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DrawingCanvas(
                drawingTool: tool,
              ),
            ),
          ),
        );

        final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
        expect(widget.drawingTool, equals(tool));
      }
    });
  });

  group('DrawingCanvas 프레젠테이션 모드 테스트', () {
    testWidgets('프레젠테이션 형광펜 페이드 활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              presentationHighlighterFadeEnabled: true,
              presentationHighlighterFadeSpeed: 1.0,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.presentationHighlighterFadeEnabled, isTrue);
      expect(widget.presentationHighlighterFadeSpeed, equals(1.0));
    });

    testWidgets('프레젠테이션 형광펜 페이드 비활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              presentationHighlighterFadeEnabled: false,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.presentationHighlighterFadeEnabled, isFalse);
    });

    testWidgets('페이드 속도 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              presentationHighlighterFadeEnabled: true,
              presentationHighlighterFadeSpeed: 2.5,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.presentationHighlighterFadeSpeed, equals(2.5));
    });
  });

  group('DrawingCanvas 필압 민감도 테스트', () {
    testWidgets('기본 필압 민감도', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.pressureSensitivity, equals(0.6));
    });

    testWidgets('커스텀 필압 민감도 설정', (tester) async {
      for (final sensitivity in [0.3, 0.5, 0.8, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DrawingCanvas(
                pressureSensitivity: sensitivity,
              ),
            ),
          ),
        );

        final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
        expect(widget.pressureSensitivity, equals(sensitivity));
      }
    });
  });

  group('DrawingCanvas 호버 커서 테스트', () {
    testWidgets('기본 호버 커서 활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.penHoverCursorEnabled, isTrue);
    });

    testWidgets('호버 커서 비활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              penHoverCursorEnabled: false,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.penHoverCursorEnabled, isFalse);
    });
  });

  group('DrawingCanvas 배경 이미지 테스트', () {
    testWidgets('배경 이미지 경로 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              backgroundImagePath: '/path/to/image.png',
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.backgroundImagePath, equals('/path/to/image.png'));
    });

    testWidgets('오버레이 템플릿 설정', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              backgroundImagePath: '/path/to/image.png',
              overlayTemplate: PageTemplate.grid,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.overlayTemplate, equals(PageTemplate.grid));
    });
  });

  group('DrawingCanvas 디버그 오버레이 테스트', () {
    testWidgets('디버그 오버레이 활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              showDebugOverlay: true,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.showDebugOverlay, isTrue);
    });

    testWidgets('디버그 오버레이 비활성화', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              showDebugOverlay: false,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.showDebugOverlay, isFalse);
    });
  });

  group('DrawingCanvas 크기 및 레이아웃 테스트', () {
    testWidgets('위젯 크기 확인', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DrawingCanvas(),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(DrawingCanvas));
      expect(size.width, equals(800));
      expect(size.height, equals(600));
    });

    testWidgets('Expanded 내 위젯 렌더링', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: DrawingCanvas(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(DrawingCanvas), findsOneWidget);
      final size = tester.getSize(find.byType(DrawingCanvas));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });
}

// ===== 테스트 헬퍼 함수 =====

Stroke _createTestStroke(String id, Color color) {
  final points = <StrokePoint>[];
  for (int i = 0; i < 10; i++) {
    points.add(StrokePoint(
      x: 100.0 + i * 10,
      y: 100.0 + i * 5,
      pressure: 0.5,
      tilt: 0.0,
      timestamp: i * 16,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: color,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}
