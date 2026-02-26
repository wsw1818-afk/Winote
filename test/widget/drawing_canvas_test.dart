import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/presentation/widgets/canvas/drawing_canvas.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/core/providers/drawing_state.dart';

void main() {
  group('DrawingCanvas 위젯 기본 테스트', () {
    testWidgets('DrawingCanvas 렌더링 성공', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(),
          ),
        ),
      );

      // 위젯이 렌더링되었는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('기본 속성값 적용 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              strokeColor: Colors.red,
              strokeWidth: 5.0,
              toolType: ToolType.pen,
              drawingTool: DrawingTool.pen,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.strokeColor, equals(Colors.red));
      expect(widget.strokeWidth, equals(5.0));
      expect(widget.toolType, equals(ToolType.pen));
      expect(widget.drawingTool, equals(DrawingTool.pen));
    });

    testWidgets('필압 민감도 속성 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              pressureSensitivity: 0.4,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.pressureSensitivity, equals(0.4));
    });

    testWidgets('호버 커서 활성화 속성 전달 확인', (WidgetTester tester) async {
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
      expect(widget.penHoverCursorEnabled, equals(false));
    });

    testWidgets('형광펜 설정 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              highlighterColor: Colors.yellow,
              highlighterWidth: 25.0,
              highlighterOpacity: 0.5,
              toolType: ToolType.highlighter,
              drawingTool: DrawingTool.highlighter,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.highlighterColor, equals(Colors.yellow));
      expect(widget.highlighterWidth, equals(25.0));
      expect(widget.highlighterOpacity, equals(0.5));
    });

    testWidgets('지우개 설정 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              eraserWidth: 30.0,
              toolType: ToolType.eraser,
              drawingTool: DrawingTool.eraser,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.eraserWidth, equals(30.0));
    });

    testWidgets('템플릿 설정 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              pageTemplate: PageTemplate.lined,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.pageTemplate, equals(PageTemplate.lined));
    });

    testWidgets('올가미 색상 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              lassoColor: Colors.blue,
              drawingTool: DrawingTool.lasso,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.lassoColor, equals(Colors.blue));
    });

    testWidgets('프레젠테이션 형광펜 설정 전달 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(
              presentationHighlighterFadeEnabled: false,
              presentationHighlighterFadeSpeed: 2.0,
              drawingTool: DrawingTool.presentationHighlighter,
            ),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.presentationHighlighterFadeEnabled, equals(false));
      expect(widget.presentationHighlighterFadeSpeed, equals(2.0));
    });
  });

  group('DrawingCanvas 콜백 테스트', () {
    testWidgets('onStrokesChanged 콜백 호출 가능', (WidgetTester tester) async {
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

      // 콜백이 연결되었는지 확인
      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));
      expect(widget.onStrokesChanged, isNotNull);
    });

    testWidgets('onUndo/onRedo 콜백 연결 확인', (WidgetTester tester) async {
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
    });
  });

  group('DrawingCanvas 기본값 테스트', () {
    testWidgets('모든 기본값 확인', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DrawingCanvas(),
          ),
        ),
      );

      final widget = tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));

      // 기본값들 확인
      expect(widget.strokeColor, equals(Colors.black));
      expect(widget.strokeWidth, equals(2.0));
      expect(widget.eraserWidth, equals(20.0));
      expect(widget.highlighterOpacity, equals(0.4));
      expect(widget.toolType, equals(ToolType.pen));
      expect(widget.drawingTool, equals(DrawingTool.pen));
      expect(widget.pageTemplate, equals(PageTemplate.grid));
      expect(widget.pressureSensitivity, equals(0.6));
      expect(widget.penHoverCursorEnabled, equals(true));
      expect(widget.canUndo, equals(false));
      expect(widget.canRedo, equals(false));
    });
  });
}
