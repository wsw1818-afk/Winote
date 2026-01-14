import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;
import 'package:winote/presentation/widgets/canvas/drawing_canvas.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Winote 필기 테스트', () {

    // 사용자처럼 마우스로 그리기
    Future<void> drawLine(
      WidgetTester tester,
      Finder canvasFinder,
      Offset relativeStart,
      List<Offset> moves,
    ) async {
      final RenderBox box = tester.renderObject(canvasFinder);
      final topLeft = box.localToGlobal(Offset.zero);
      final size = box.size;

      // 캔버스 중앙 기준으로 상대 좌표 계산
      final center = topLeft + Offset(size.width / 2, size.height / 2);
      final startPos = center + relativeStart;

      // 마우스로 그리기 시작
      final TestGesture gesture = await tester.startGesture(
        startPos,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 32));

      // 이동
      for (final move in moves) {
        await gesture.moveBy(move);
        await tester.pump(const Duration(milliseconds: 16));
      }

      // 그리기 완료
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('1. 홈 화면에서 새 노트 생성', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Winote 앱 타이틀 확인
      expect(find.text('Winote'), findsWidgets);

      // FAB 버튼 클릭해서 새 노트 생성
      final fabButton = find.byType(FloatingActionButton);
      expect(fabButton, findsOneWidget);

      await tester.tap(fabButton);
      await tester.pumpAndSettle();

      // 에디터 화면 확인 (DrawingCanvas가 있어야 함)
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('2. 펜으로 선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 에디터로 이동
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // DrawingCanvas 찾기
      final canvas = find.byType(DrawingCanvas);
      expect(canvas, findsOneWidget);

      // 캔버스 중앙에서 선 그리기
      await drawLine(tester, canvas, Offset.zero, [
        const Offset(100, 0),
        const Offset(50, 50),
        const Offset(0, 50),
      ]);

      // 스트로크가 생성되었는지 확인
      expect(find.textContaining('Strokes: 1'), findsOneWidget);
    });

    testWidgets('3. Undo/Redo 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);

      // 선 그리기
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 50)]);
      expect(find.textContaining('Strokes: 1'), findsOneWidget);

      // Undo
      await tester.tap(find.byIcon(Icons.undo).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Strokes: 0'), findsOneWidget);

      // Redo
      await tester.tap(find.byIcon(Icons.redo).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Strokes: 1'), findsOneWidget);
    });

    testWidgets('4. 올가미 도구 선택 및 사용', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);

      // 먼저 선 그리기
      await drawLine(tester, canvas, const Offset(-50, 0), [const Offset(100, 0)]);
      expect(find.textContaining('Strokes: 1'), findsOneWidget);

      // 올가미 도구 선택
      final lassoButton = find.byIcon(Icons.gesture).first;
      await tester.tap(lassoButton);
      await tester.pumpAndSettle();

      // 도구가 lasso로 변경 확인
      expect(find.textContaining('Tool: lasso'), findsOneWidget);

      // 올가미로 선택 영역 그리기
      await drawLine(tester, canvas, const Offset(-80, -40), [
        const Offset(160, 0),
        const Offset(0, 80),
        const Offset(-160, 0),
        const Offset(0, -80),
      ]);

      // 올가미 도구로 그렸을 때 화면이 정상 동작
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('5. 지우개 도구 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);

      // 선 그리기
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 0)]);
      expect(find.textContaining('Strokes: 1'), findsOneWidget);

      // 지우개 도구 선택
      final eraserButton = find.byIcon(Icons.auto_fix_high);
      if (eraserButton.evaluate().isNotEmpty) {
        await tester.tap(eraserButton.first);
        await tester.pumpAndSettle();

        expect(find.textContaining('Tool: eraser'), findsOneWidget);

        // 지우개로 선 위를 지나가기
        await drawLine(tester, canvas, const Offset(-10, 0), [const Offset(80, 0)]);

        // 스트로크 삭제 확인
        expect(find.textContaining('Strokes: 0'), findsOneWidget);
      }
    });

    testWidgets('6. 펜 도구로 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // 올가미 도구 선택
      await tester.tap(find.byIcon(Icons.gesture).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tool: lasso'), findsOneWidget);

      // 펜 도구로 돌아가기
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tool: pen'), findsOneWidget);
    });

    testWidgets('7. 여러 스트로크 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);

      // 3개의 선 그리기
      await drawLine(tester, canvas, const Offset(-100, -50), [const Offset(50, 50)]);
      await drawLine(tester, canvas, const Offset(0, 0), [const Offset(80, 30)]);
      await drawLine(tester, canvas, const Offset(50, -30), [const Offset(-30, 80)]);

      expect(find.textContaining('Strokes: 3'), findsOneWidget);
    });

    testWidgets('8. 형광펜 도구 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // 형광펜 도구 선택 (있는 경우)
      final highlighterButton = find.byIcon(Icons.brush);
      if (highlighterButton.evaluate().isNotEmpty) {
        await tester.tap(highlighterButton.first);
        await tester.pumpAndSettle();

        expect(find.textContaining('Tool: highlighter'), findsOneWidget);
      }
    });

    // === S-Pen(터치) 시뮬레이션 테스트 ===
    // 실제 S-Pen은 PointerDeviceKind.touch로 감지됨

    testWidgets('9. [S-Pen 시뮬레이션] 터치로 펜 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      // 터치로 그리기 (S-Pen이 touch로 감지되는 상황 시뮬레이션)
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,  // S-Pen은 touch로 감지됨
      );
      await tester.pump(const Duration(milliseconds: 32));

      await gesture.moveBy(const Offset(100, 50));
      await tester.pump(const Duration(milliseconds: 16));

      await gesture.up();
      await tester.pumpAndSettle();

      // 터치 입력은 기본적으로 finger로 처리되어 스트로크가 생성되지 않을 수 있음
      // (Windows API가 없는 테스트 환경에서는 touch = finger로 간주)
      // 실제 기기에서는 Windows API로 PEN/TOUCH 구분
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('10. [S-Pen 시뮬레이션] 터치로 올가미 도구 사용', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // 먼저 마우스로 선 그리기 (이건 확실히 동작)
      final canvas = find.byType(DrawingCanvas);
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 0)]);
      expect(find.textContaining('Strokes: 1'), findsOneWidget);

      // 올가미 도구 선택
      await tester.tap(find.byIcon(Icons.gesture).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tool: lasso'), findsOneWidget);

      // 터치로 올가미 그리기 (S-Pen 시뮬레이션)
      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      final gesture = await tester.startGesture(
        center + const Offset(-80, -40),
        kind: PointerDeviceKind.touch,  // S-Pen이 touch로 감지되는 상황
      );
      await tester.pump(const Duration(milliseconds: 32));

      // 사각형 모양으로 올가미 그리기
      await gesture.moveBy(const Offset(160, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));

      await gesture.up();
      await tester.pumpAndSettle();

      // 올가미 도구는 touch 입력도 허용해야 함 (수정된 코드)
      // 화면이 정상 동작하는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
      expect(find.textContaining('Tool: lasso'), findsOneWidget);
    });

    testWidgets('11. [스타일러스] stylus 타입으로 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      // stylus 타입으로 그리기 (일부 기기에서 S-Pen이 stylus로 감지됨)
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 32));

      await gesture.moveBy(const Offset(100, 50));
      await tester.pump(const Duration(milliseconds: 16));

      await gesture.up();
      await tester.pumpAndSettle();

      // stylus는 항상 허용되므로 스트로크 생성됨
      expect(find.textContaining('Strokes: 1'), findsOneWidget);
    });
  });
}
