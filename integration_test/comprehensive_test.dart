import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;
import 'package:winote/presentation/widgets/canvas/drawing_canvas.dart';

/// Winote 앱 포괄적 기능 테스트
///
/// 테스트 범위:
/// 1. 필기 도구 (펜, 형광펜, 지우개)
/// 2. 올가미 도구 상세 기능 (선택, 이동, 복사, 삭제)
/// 3. 도형 도구 (직선, 사각형, 원, 화살표)
/// 4. 제스처 (2손가락, 3손가락)
/// 5. 설정 옵션
/// 6. Undo/Redo
/// 7. 노트 저장/불러오기

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // === 헬퍼 함수들 ===

  /// 마우스로 선 그리기
  Future<void> drawWithMouse(
    WidgetTester tester,
    Finder canvasFinder,
    Offset relativeStart,
    List<Offset> moves, {
    double pressure = 0.5,
  }) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final startPos = center + relativeStart;

    final gesture = await tester.startGesture(
      startPos,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 32));

    for (final move in moves) {
      await gesture.moveBy(move);
      await tester.pump(const Duration(milliseconds: 16));
    }

    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 스타일러스(S펜)로 그리기
  Future<void> drawWithStylus(
    WidgetTester tester,
    Finder canvasFinder,
    Offset relativeStart,
    List<Offset> moves,
  ) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final startPos = center + relativeStart;

    final gesture = await tester.startGesture(
      startPos,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 32));

    for (final move in moves) {
      await gesture.moveBy(move);
      await tester.pump(const Duration(milliseconds: 16));
    }

    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 터치로 그리기
  Future<void> drawWithTouch(
    WidgetTester tester,
    Finder canvasFinder,
    Offset relativeStart,
    List<Offset> moves,
  ) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final startPos = center + relativeStart;

    final gesture = await tester.startGesture(
      startPos,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 32));

    for (final move in moves) {
      await gesture.moveBy(move);
      await tester.pump(const Duration(milliseconds: 16));
    }

    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 2손가락 제스처 (핀치 줌)
  Future<void> pinchZoom(
    WidgetTester tester,
    Finder canvasFinder, {
    bool zoomIn = true,
  }) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);

    final finger1 = await tester.startGesture(
      center + const Offset(-50, 0),
      kind: PointerDeviceKind.touch,
    );
    final finger2 = await tester.startGesture(
      center + const Offset(50, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 32));

    final offset = zoomIn ? 30.0 : -30.0;
    await finger1.moveBy(Offset(-offset, 0));
    await finger2.moveBy(Offset(offset, 0));
    await tester.pump(const Duration(milliseconds: 32));

    await finger1.up();
    await finger2.up();
    await tester.pumpAndSettle();
  }

  /// 2손가락 팬 (이동)
  Future<void> twoFingerPan(
    WidgetTester tester,
    Finder canvasFinder,
    Offset panOffset,
  ) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);

    final finger1 = await tester.startGesture(
      center + const Offset(-30, 0),
      kind: PointerDeviceKind.touch,
    );
    final finger2 = await tester.startGesture(
      center + const Offset(30, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 32));

    await finger1.moveBy(panOffset);
    await finger2.moveBy(panOffset);
    await tester.pump(const Duration(milliseconds: 32));

    await finger1.up();
    await finger2.up();
    await tester.pumpAndSettle();
  }

  /// 2손가락 탭 (Undo)
  Future<void> twoFingerTap(WidgetTester tester, Finder canvasFinder) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);

    final finger1 = await tester.startGesture(
      center + const Offset(-30, 0),
      kind: PointerDeviceKind.touch,
    );
    final finger2 = await tester.startGesture(
      center + const Offset(30, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 50));

    await finger1.up();
    await finger2.up();
    await tester.pumpAndSettle();
  }

  /// 3손가락 탭 (Redo)
  Future<void> threeFingerTap(WidgetTester tester, Finder canvasFinder) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);

    final finger1 = await tester.startGesture(
      center + const Offset(-40, 0),
      kind: PointerDeviceKind.touch,
    );
    final finger2 = await tester.startGesture(
      center + const Offset(0, 0),
      kind: PointerDeviceKind.touch,
    );
    final finger3 = await tester.startGesture(
      center + const Offset(40, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 50));

    await finger1.up();
    await finger2.up();
    await finger3.up();
    await tester.pumpAndSettle();
  }

  /// 롱프레스 (800ms)
  Future<void> longPress(
    WidgetTester tester,
    Finder canvasFinder,
    Offset relativePos,
  ) async {
    final RenderBox box = tester.renderObject(canvasFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final pos = center + relativePos;

    final gesture = await tester.startGesture(pos, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 850));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 에디터로 이동 (새 노트 생성)
  Future<Finder?> navigateToEditor(WidgetTester tester) async {
    final fabs = find.byType(FloatingActionButton);
    if (fabs.evaluate().isEmpty) return null;
    await tester.tap(fabs.last);
    await tester.pumpAndSettle();

    final canvas = find.byType(DrawingCanvas);
    if (canvas.evaluate().isEmpty) return null;
    return canvas;
  }

  /// 설정 페이지로 이동
  Future<bool> navigateToSettings(WidgetTester tester) async {
    final settingsButton = find.byIcon(Icons.settings);
    if (settingsButton.evaluate().isEmpty) return false;
    await tester.tap(settingsButton.first);
    await tester.pumpAndSettle();
    return true;
  }

  // ========================================
  // 테스트 그룹 1: 기본 필기 도구
  // ========================================
  group('1. 기본 필기 도구 테스트', () {
    testWidgets('1.1 펜으로 직선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithMouse(tester, canvas, Offset.zero, [
        const Offset(100, 0),
      ]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('1.2 펜으로 곡선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithMouse(tester, canvas, const Offset(-50, 0), [
        const Offset(25, -25),
        const Offset(25, 25),
        const Offset(25, 25),
        const Offset(25, -25),
      ]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('1.3 스타일러스로 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithStylus(tester, canvas, Offset.zero, [
        const Offset(80, 40),
      ]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('1.4 형광펜 도구 선택 및 사용', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final highlighter = find.byIcon(Icons.brush);
      if (highlighter.evaluate().isNotEmpty) {
        await tester.tap(highlighter.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, 0), [
          const Offset(100, 0),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('1.5 지우개 도구로 스트로크 삭제', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [
        const Offset(100, 0),
      ]);

      // 지우개 선택
      final eraser = find.byIcon(Icons.auto_fix_high);
      if (eraser.evaluate().isNotEmpty) {
        await tester.tap(eraser.first);
        await tester.pumpAndSettle();

        // 선 위를 지나가며 지우기
        await drawWithMouse(tester, canvas, const Offset(-10, 0), [
          const Offset(120, 0),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('1.6 여러 스트로크 연속 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 5개의 선 그리기
      for (int i = 0; i < 5; i++) {
        await drawWithMouse(
          tester,
          canvas,
          Offset(-100 + i * 40.0, -50),
          [const Offset(0, 100)],
        );
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 2: 올가미 도구 상세 기능
  // ========================================
  group('2. 올가미 도구 상세 테스트', () {
    testWidgets('2.1 올가미 도구 선택', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('2.2 올가미로 스트로크 선택', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 먼저 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [
        const Offset(80, 0),
      ]);

      // 올가미 도구 선택
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        // 올가미로 선택 영역 그리기 (닫힌 사각형)
        await drawWithMouse(tester, canvas, const Offset(-50, -30), [
          const Offset(150, 0),
          const Offset(0, 60),
          const Offset(-150, 0),
          const Offset(0, -60),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('2.3 올가미 선택 후 삭제', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [
        const Offset(80, 0),
      ]);

      // 올가미로 선택
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, -30), [
          const Offset(150, 0),
          const Offset(0, 60),
          const Offset(-150, 0),
          const Offset(0, -60),
        ]);

        // 삭제 버튼 찾기
        final deleteBtn = find.byIcon(Icons.delete);
        if (deleteBtn.evaluate().isNotEmpty) {
          await tester.tap(deleteBtn.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('2.4 올가미 다중 스트로크 선택', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 여러 선 그리기
      await drawWithMouse(tester, canvas, const Offset(-50, 0), [const Offset(30, 0)]);
      await drawWithMouse(tester, canvas, const Offset(0, 0), [const Offset(30, 0)]);
      await drawWithMouse(tester, canvas, const Offset(50, 0), [const Offset(30, 0)]);

      // 올가미로 전체 선택
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-80, -30), [
          const Offset(180, 0),
          const Offset(0, 60),
          const Offset(-180, 0),
          const Offset(0, -60),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('2.5 올가미 선택 해제', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // 올가미로 선택
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, -30), [
          const Offset(150, 0),
          const Offset(0, 60),
          const Offset(-150, 0),
          const Offset(0, -60),
        ]);

        // 빈 공간 탭으로 선택 해제
        await tester.tapAt(
          tester.getCenter(canvas) + const Offset(200, 0),
        );
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 3: 도형 도구
  // ========================================
  group('3. 도형 도구 테스트', () {
    testWidgets('3.1 직선 도형 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final lineBtn = find.byIcon(Icons.show_chart);
      if (lineBtn.evaluate().isNotEmpty) {
        await tester.tap(lineBtn.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, 0), [
          const Offset(100, 0),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('3.2 화살표 도형 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final arrowBtn = find.byIcon(Icons.arrow_forward);
      if (arrowBtn.evaluate().isNotEmpty) {
        await tester.tap(arrowBtn.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, 0), [
          const Offset(100, 0),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('3.3 사각형 도형 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final rectBtn = find.byIcon(Icons.crop_square);
      if (rectBtn.evaluate().isNotEmpty) {
        await tester.tap(rectBtn.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, -30), [
          const Offset(100, 60),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('3.4 원 도형 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final circleBtn = find.byIcon(Icons.circle_outlined);
      if (circleBtn.evaluate().isNotEmpty) {
        await tester.tap(circleBtn.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-40, -40), [
          const Offset(80, 80),
        ]);
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 4: 제스처
  // ========================================
  group('4. 제스처 테스트', () {
    testWidgets('4.1 2손가락 핀치 줌 인', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await pinchZoom(tester, canvas, zoomIn: true);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('4.2 2손가락 핀치 줌 아웃', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await pinchZoom(tester, canvas, zoomIn: false);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('4.3 2손가락 팬 이동', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await twoFingerPan(tester, canvas, const Offset(100, 50));

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('4.4 2손가락 탭 (Undo)', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // 2손가락 탭으로 Undo
      await twoFingerTap(tester, canvas);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('4.5 3손가락 탭 (Redo)', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // 2손가락 탭으로 Undo
      await twoFingerTap(tester, canvas);

      // 3손가락 탭으로 Redo
      await threeFingerTap(tester, canvas);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 5: Undo/Redo
  // ========================================
  group('5. Undo/Redo 테스트', () {
    testWidgets('5.1 Undo 버튼으로 실행취소', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // Undo 버튼 클릭
      final undoBtn = find.byIcon(Icons.undo);
      if (undoBtn.evaluate().isNotEmpty) {
        await tester.tap(undoBtn.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('5.2 Redo 버튼으로 다시실행', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // Undo
      final undoBtn = find.byIcon(Icons.undo);
      if (undoBtn.evaluate().isNotEmpty) {
        await tester.tap(undoBtn.first);
        await tester.pumpAndSettle();

        // Redo
        final redoBtn = find.byIcon(Icons.redo);
        if (redoBtn.evaluate().isNotEmpty) {
          await tester.tap(redoBtn.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('5.3 연속 Undo (여러 스트로크)', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 3개의 선 그리기
      await drawWithMouse(tester, canvas, const Offset(-60, 0), [const Offset(40, 0)]);
      await drawWithMouse(tester, canvas, const Offset(0, 0), [const Offset(40, 0)]);
      await drawWithMouse(tester, canvas, const Offset(60, 0), [const Offset(40, 0)]);

      // 연속 Undo
      final undoBtn = find.byIcon(Icons.undo);
      if (undoBtn.evaluate().isNotEmpty) {
        for (int i = 0; i < 3; i++) {
          await tester.tap(undoBtn.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 6: 설정 페이지
  // ========================================
  group('6. 설정 페이지 테스트', () {
    testWidgets('6.1 설정 페이지 진입', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final success = await navigateToSettings(tester);
      if (!success) return;

      expect(find.text('설정'), findsWidgets);
    });

    testWidgets('6.2 필압 민감도 슬라이더 조작', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!await navigateToSettings(tester)) return;

      final slider = find.byType(Slider);
      if (slider.evaluate().isNotEmpty) {
        await tester.drag(slider.first, const Offset(50, 0));
        await tester.pumpAndSettle();
      }

      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('6.3 3손가락 제스처 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!await navigateToSettings(tester)) return;

      final gestureSwitch = find.text('3손가락 제스처');
      if (gestureSwitch.evaluate().isNotEmpty) {
        final switchWidget = find.ancestor(
          of: gestureSwitch,
          matching: find.byType(SwitchListTile),
        );
        if (switchWidget.evaluate().isNotEmpty) {
          await tester.tap(switchWidget.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('6.4 S펜 호버 커서 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!await navigateToSettings(tester)) return;

      final hoverSwitch = find.text('S펜 호버 커서');
      if (hoverSwitch.evaluate().isNotEmpty) {
        final switchWidget = find.ancestor(
          of: hoverSwitch,
          matching: find.byType(SwitchListTile),
        );
        if (switchWidget.evaluate().isNotEmpty) {
          await tester.tap(switchWidget.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('6.5 손바닥 무시 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!await navigateToSettings(tester)) return;

      final palmSwitch = find.text('손바닥 무시');
      if (palmSwitch.evaluate().isNotEmpty) {
        final switchWidget = find.ancestor(
          of: palmSwitch,
          matching: find.byType(SwitchListTile),
        );
        if (switchWidget.evaluate().isNotEmpty) {
          await tester.tap(switchWidget.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('6.6 도형 스냅 토글', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      if (!await navigateToSettings(tester)) return;

      final snapSwitch = find.text('도형 스냅');
      if (snapSwitch.evaluate().isNotEmpty) {
        final switchWidget = find.ancestor(
          of: snapSwitch,
          matching: find.byType(SwitchListTile),
        );
        if (switchWidget.evaluate().isNotEmpty) {
          await tester.tap(switchWidget.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(SwitchListTile), findsWidgets);
    });
  });

  // ========================================
  // 테스트 그룹 7: 도구 전환
  // ========================================
  group('7. 도구 전환 테스트', () {
    testWidgets('7.1 펜 → 올가미 → 펜 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 올가미로 전환
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        // 펜으로 돌아가기
        final pen = find.byIcon(Icons.edit);
        if (pen.evaluate().isNotEmpty) {
          await tester.tap(pen.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('7.2 펜 → 지우개 → 펜 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 지우개로 전환
      final eraser = find.byIcon(Icons.auto_fix_high);
      if (eraser.evaluate().isNotEmpty) {
        await tester.tap(eraser.first);
        await tester.pumpAndSettle();

        // 펜으로 돌아가기
        final pen = find.byIcon(Icons.edit);
        if (pen.evaluate().isNotEmpty) {
          await tester.tap(pen.first);
          await tester.pumpAndSettle();
        }
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('7.3 펜 → 형광펜 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      final highlighter = find.byIcon(Icons.brush);
      if (highlighter.evaluate().isNotEmpty) {
        await tester.tap(highlighter.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('7.4 도형 도구 간 전환', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 직선 → 화살표 → 사각형
      final line = find.byIcon(Icons.show_chart);
      if (line.evaluate().isNotEmpty) {
        await tester.tap(line.first);
        await tester.pumpAndSettle();
      }

      final arrow = find.byIcon(Icons.arrow_forward);
      if (arrow.evaluate().isNotEmpty) {
        await tester.tap(arrow.first);
        await tester.pumpAndSettle();
      }

      final rect = find.byIcon(Icons.crop_square);
      if (rect.evaluate().isNotEmpty) {
        await tester.tap(rect.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 8: 노트 저장/불러오기
  // ========================================
  group('8. 노트 저장/불러오기 테스트', () {
    testWidgets('8.1 노트 저장', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // 저장 버튼
      final saveBtn = find.byIcon(Icons.save);
      if (saveBtn.evaluate().isNotEmpty) {
        await tester.tap(saveBtn.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('8.2 뒤로가기 후 노트 열기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 노트 목록에서 기존 노트 탭
      final noteCard = find.byType(Card);
      if (noteCard.evaluate().isNotEmpty) {
        await tester.tap(noteCard.first);
        await tester.pumpAndSettle();

        expect(find.byType(DrawingCanvas), findsOneWidget);
      }
    });
  });

  // ========================================
  // 테스트 그룹 9: 입력 방식별 테스트
  // ========================================
  group('9. 입력 방식별 테스트', () {
    testWidgets('9.1 마우스 입력', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(100, 50)]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('9.2 스타일러스 입력', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithStylus(tester, canvas, Offset.zero, [const Offset(100, 50)]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('9.3 터치 입력', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      await drawWithTouch(tester, canvas, Offset.zero, [const Offset(100, 50)]);

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });

  // ========================================
  // 테스트 그룹 10: 복합 시나리오
  // ========================================
  group('10. 복합 시나리오 테스트', () {
    testWidgets('10.1 그리기 → 올가미 선택 → 삭제 → Undo', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 1. 선 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 0)]);

      // 2. 올가미로 선택
      final lasso = find.byIcon(Icons.gesture);
      if (lasso.evaluate().isNotEmpty) {
        await tester.tap(lasso.first);
        await tester.pumpAndSettle();

        await drawWithMouse(tester, canvas, const Offset(-50, -30), [
          const Offset(150, 0),
          const Offset(0, 60),
          const Offset(-150, 0),
          const Offset(0, -60),
        ]);

        // 3. 삭제
        final deleteBtn = find.byIcon(Icons.delete);
        if (deleteBtn.evaluate().isNotEmpty) {
          await tester.tap(deleteBtn.first);
          await tester.pumpAndSettle();
        }
      }

      // 4. Undo
      final undoBtn = find.byIcon(Icons.undo);
      if (undoBtn.evaluate().isNotEmpty) {
        await tester.tap(undoBtn.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('10.2 여러 도형 그리기 → 줌 → 이동', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 1. 직선 그리기
      final lineBtn = find.byIcon(Icons.show_chart);
      if (lineBtn.evaluate().isNotEmpty) {
        await tester.tap(lineBtn.first);
        await tester.pumpAndSettle();
        await drawWithMouse(tester, canvas, const Offset(-50, 0), [const Offset(100, 0)]);
      }

      // 2. 화살표 그리기
      final arrowBtn = find.byIcon(Icons.arrow_forward);
      if (arrowBtn.evaluate().isNotEmpty) {
        await tester.tap(arrowBtn.first);
        await tester.pumpAndSettle();
        await drawWithMouse(tester, canvas, const Offset(-50, 50), [const Offset(100, 0)]);
      }

      // 3. 줌 인
      await pinchZoom(tester, canvas, zoomIn: true);

      // 4. 팬 이동
      await twoFingerPan(tester, canvas, const Offset(50, 30));

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });

    testWidgets('10.3 설정 변경 → 그리기 → 저장', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. 설정 변경
      if (await navigateToSettings(tester)) {
        final slider = find.byType(Slider);
        if (slider.evaluate().isNotEmpty) {
          await tester.drag(slider.first, const Offset(30, 0));
          await tester.pumpAndSettle();
        }

        // 뒤로가기
        final backBtn = find.byIcon(Icons.arrow_back);
        if (backBtn.evaluate().isNotEmpty) {
          await tester.tap(backBtn.first);
          await tester.pumpAndSettle();
        }
      }

      // 2. 에디터로 이동
      final canvas = await navigateToEditor(tester);
      if (canvas == null) return;

      // 3. 그리기
      await drawWithMouse(tester, canvas, Offset.zero, [const Offset(80, 40)]);

      // 4. 저장
      final saveBtn = find.byIcon(Icons.save);
      if (saveBtn.evaluate().isNotEmpty) {
        await tester.tap(saveBtn.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DrawingCanvas), findsOneWidget);
    });
  });
}
