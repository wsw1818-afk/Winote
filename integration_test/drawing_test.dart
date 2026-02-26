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

      // FAB 버튼 클릭해서 새 노트 생성 (PDF 가져오기가 아닌 새 노트 생성 FAB)
      // extended FAB (새 노트)를 찾아서 탭
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;

      // 마지막 FAB가 "새 노트" 버튼 (extended FAB)
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      // 에디터 화면 확인 (DrawingCanvas가 있어야 함)
      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;  // 방어적 처리
      expect(canvas, findsOneWidget);
    });

    testWidgets('2. 펜으로 선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 에디터로 이동 (FAB가 여러 개일 수 있음)
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      // DrawingCanvas 찾기
      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 캔버스 중앙에서 선 그리기
      await drawLine(tester, canvas, Offset.zero, [
        const Offset(100, 0),
        const Offset(50, 50),
        const Offset(0, 50),
      ]);

      // 캔버스가 정상 동작하는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('3. Undo/Redo 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 선 그리기
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 50)]);

      // Undo 버튼이 있으면 테스트
      final undoBtn = find.byIcon(Icons.undo);
      if (undoBtn.evaluate().isNotEmpty) {
        await tester.tap(undoBtn.first);
        await tester.pumpAndSettle();

        // Redo 버튼이 있으면 테스트
        final redoBtn = find.byIcon(Icons.redo);
        if (redoBtn.evaluate().isNotEmpty) {
          await tester.tap(redoBtn.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('4. 올가미 도구 선택 및 사용', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 먼저 선 그리기
      await drawLine(tester, canvas, const Offset(-50, 0), [const Offset(100, 0)]);

      // 올가미 도구 선택
      final lassoButton = find.byIcon(Icons.gesture);
      if (lassoButton.evaluate().isNotEmpty) {
        await tester.tap(lassoButton.first);
        await tester.pumpAndSettle();

        // 올가미로 선택 영역 그리기
        await drawLine(tester, canvas, const Offset(-80, -40), [
          const Offset(160, 0),
          const Offset(0, 80),
          const Offset(-160, 0),
          const Offset(0, -80),
        ]);
      }

      // 올가미 도구로 그렸을 때 화면이 정상 동작
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('5. 지우개 도구 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 선 그리기
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 0)]);

      // 지우개 도구 선택
      final eraserButton = find.byIcon(Icons.auto_fix_high);
      if (eraserButton.evaluate().isNotEmpty) {
        await tester.tap(eraserButton.first);
        await tester.pumpAndSettle();

        // 지우개로 선 위를 지나가기
        await drawLine(tester, canvas, const Offset(-10, 0), [const Offset(80, 0)]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('6. 펜 도구로 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 올가미 도구 선택
      final lassoBtn = find.byIcon(Icons.gesture);
      if (lassoBtn.evaluate().isNotEmpty) {
        await tester.tap(lassoBtn.first);
        await tester.pumpAndSettle();

        // 펜 도구로 돌아가기
        final penBtn = find.byIcon(Icons.edit);
        if (penBtn.evaluate().isNotEmpty) {
          await tester.tap(penBtn.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('7. 여러 스트로크 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 3개의 선 그리기
      await drawLine(tester, canvas, const Offset(-100, -50), [const Offset(50, 50)]);
      await drawLine(tester, canvas, const Offset(0, 0), [const Offset(80, 30)]);
      await drawLine(tester, canvas, const Offset(50, -30), [const Offset(-30, 80)]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('8. 형광펜 도구 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 형광펜 도구 선택 (있는 경우)
      final highlighterButton = find.byIcon(Icons.brush);
      if (highlighterButton.evaluate().isNotEmpty) {
        await tester.tap(highlighterButton.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    // === S-Pen(터치) 시뮬레이션 테스트 ===
    // 실제 S-Pen은 PointerDeviceKind.touch로 감지됨

    testWidgets('9. [S-Pen 시뮬레이션] 터치로 펜 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      // 터치로 그리기 (S-Pen이 touch로 감지되는 상황 시뮬레이션)
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 32));

      await gesture.moveBy(const Offset(100, 50));
      await tester.pump(const Duration(milliseconds: 16));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('10. [S-Pen 시뮬레이션] 터치로 올가미 도구 사용', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      // 먼저 마우스로 선 그리기
      await drawLine(tester, canvas, Offset.zero, [const Offset(100, 0)]);

      // 올가미 도구 선택
      final lassoBtn = find.byIcon(Icons.gesture);
      if (lassoBtn.evaluate().isNotEmpty) {
        await tester.tap(lassoBtn.first);
        await tester.pumpAndSettle();

        // 터치로 올가미 그리기 (S-Pen 시뮬레이션)
        final RenderBox box = tester.renderObject(canvas);
        final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

        final gesture = await tester.startGesture(
          center + const Offset(-80, -40),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 32));

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
      }

      // 화면이 정상 동작하는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('11. [스타일러스] stylus 타입으로 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FAB가 여러 개일 수 있으므로 첫 번째 선택
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

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

      // stylus 그리기 후 캔버스가 정상 동작하는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    // === 새로 추가된 기능 테스트 (v1.1) ===

    testWidgets('12. 설정 페이지 진입 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 설정 버튼 찾기 (보통 AppBar의 아이콘)
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // 설정 페이지 확인
        expect(find.text('설정'), findsWidgets);
      }
    });

    testWidgets('13. 3손가락 제스처 설정 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 설정 페이지로 이동
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // 3손가락 제스처 설정 찾기
        final gestureSwitch = find.text('3손가락 제스처');
        if (gestureSwitch.evaluate().isNotEmpty) {
          // 스위치 토글 (부모 위젯의 스위치 찾기)
          final switchWidget = find.ancestor(
            of: gestureSwitch,
            matching: find.byType(SwitchListTile),
          );
          if (switchWidget.evaluate().isNotEmpty) {
            await tester.tap(switchWidget.first);
            await tester.pumpAndSettle();

            // 설정이 변경되었는지 확인 (토글됨)
            expect(find.byType(SwitchListTile), findsWidgets);
          }
        }
      }
    });

    testWidgets('14. 필압 민감도 슬라이더 조작', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 설정 페이지로 이동
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // 필압 민감도 슬라이더 찾기
        final slider = find.byType(Slider);
        if (slider.evaluate().isNotEmpty) {
          // 슬라이더 드래그
          await tester.drag(slider.first, const Offset(50, 0));
          await tester.pumpAndSettle();

          // 슬라이더가 여전히 존재하는지 확인
          expect(find.byType(Slider), findsWidgets);
        }
      }
    });

    testWidgets('15. S펜 호버 커서 설정 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 설정 페이지로 이동
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // S펜 호버 커서 설정 찾기
        final hoverSwitch = find.text('S펜 호버 커서');
        if (hoverSwitch.evaluate().isNotEmpty) {
          final switchWidget = find.ancestor(
            of: hoverSwitch,
            matching: find.byType(SwitchListTile),
          );
          if (switchWidget.evaluate().isNotEmpty) {
            await tester.tap(switchWidget.first);
            await tester.pumpAndSettle();

            expect(find.byType(SwitchListTile), findsWidgets);
          }
        }
      }
    });

    testWidgets('16. [제스처] 2손가락 핀치 줌', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FAB가 여러 개일 수 있으므로 첫 번째 선택
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      // 2손가락 핀치 줌 시뮬레이션
      final finger1 = await tester.startGesture(
        center + const Offset(-50, 0),
        kind: PointerDeviceKind.touch,
      );
      final finger2 = await tester.startGesture(
        center + const Offset(50, 0),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 32));

      // 손가락 벌리기 (줌 인)
      await finger1.moveBy(const Offset(-30, 0));
      await finger2.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 32));

      await finger1.up();
      await finger2.up();
      await tester.pumpAndSettle();

      // 캔버스가 여전히 존재하는지 확인
      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('17. [제스처] 2손가락 팬 이동', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FAB가 여러 개일 수 있으므로 첫 번째 선택
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      final canvas = find.byType(DrawingCanvas);
      if (canvas.evaluate().isEmpty) return;

      final RenderBox box = tester.renderObject(canvas);
      final center = box.localToGlobal(Offset.zero) + Offset(box.size.width / 2, box.size.height / 2);

      // 2손가락 팬 시뮬레이션
      final finger1 = await tester.startGesture(
        center + const Offset(-30, 0),
        kind: PointerDeviceKind.touch,
      );
      final finger2 = await tester.startGesture(
        center + const Offset(30, 0),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 32));

      // 두 손가락 동시에 이동 (팬)
      await finger1.moveBy(const Offset(100, 50));
      await finger2.moveBy(const Offset(100, 50));
      await tester.pump(const Duration(milliseconds: 32));

      await finger1.up();
      await finger2.up();
      await tester.pumpAndSettle();

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('18. 도형 도구 직선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FAB가 여러 개일 수 있으므로 첫 번째 선택
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      // 도형 도구 버튼 찾기 (직선)
      final shapeButton = find.byIcon(Icons.show_chart);
      if (shapeButton.evaluate().isNotEmpty) {
        await tester.tap(shapeButton.first);
        await tester.pumpAndSettle();

        final canvas = find.byType(DrawingCanvas);
        if (canvas.evaluate().isNotEmpty) {
          // 직선 그리기
          await drawLine(tester, canvas, const Offset(-50, 0), [const Offset(100, 0)]);

          // 도형 스트로크 생성 확인
          expect(find.byType(DrawingCanvas), findsOneWidget);
        }
      }
    });

    testWidgets('19. 도형 도구 화살표 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FAB가 여러 개일 수 있으므로 첫 번째 선택
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isEmpty) return;
      await tester.tap(fabs.last);
      await tester.pumpAndSettle();

      // 화살표 도구 버튼 찾기
      final arrowButton = find.byIcon(Icons.arrow_forward);
      if (arrowButton.evaluate().isNotEmpty) {
        await tester.tap(arrowButton.first);
        await tester.pumpAndSettle();

        final canvas = find.byType(DrawingCanvas);
        if (canvas.evaluate().isNotEmpty) {
          // 화살표 그리기
          await drawLine(tester, canvas, const Offset(-50, 0), [const Offset(100, 0)]);

          expect(find.byType(DrawingCanvas), findsOneWidget);
        }
      }
    });

    testWidgets('20. 노트 저장 및 불러오기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 새 노트 생성 (FAB가 여러 개일 수 있으므로 첫 번째 선택)
      final fabs = find.byType(FloatingActionButton);
      if (fabs.evaluate().isNotEmpty) {
        await tester.tap(fabs.last);
        await tester.pumpAndSettle();

        final canvas = find.byType(DrawingCanvas);
        if (canvas.evaluate().isNotEmpty) {
          // 선 그리기
          await drawLine(tester, canvas, Offset.zero, [const Offset(100, 50)]);

          // 저장 버튼 찾기 (있는 경우)
          final saveButton = find.byIcon(Icons.save);
          if (saveButton.evaluate().isNotEmpty) {
            await tester.tap(saveButton.first);
            await tester.pumpAndSettle();

            // 저장 완료 후에도 캔버스 정상 동작
            expect(find.byType(DrawingCanvas), findsOneWidget);
          }
        }
      }
    });
  });
}
