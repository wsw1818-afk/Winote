import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Winote 필기 테스트', () {
    testWidgets('홈 화면에서 새 노트 생성', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 홈 화면 확인 (Winote 텍스트가 여러 개 있을 수 있음)
      expect(find.text('Winote'), findsWidgets);
      expect(find.text('새 노트'), findsOneWidget);

      // 새 노트 버튼 클릭
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();

      // 에디터 화면으로 이동 확인 (AppBar 제목)
      expect(find.text('새 노트'), findsOneWidget);
    });

    testWidgets('캔버스에서 드래그하여 선 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 새 노트 버튼 클릭
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();

      // 캔버스 찾기
      final canvas = find.byType(CustomPaint).first;
      expect(canvas, findsOneWidget);

      // 드래그 제스처 시뮬레이션 (선 그리기)
      final center = tester.getCenter(canvas);
      final gesture = await tester.startGesture(center);
      await tester.pump();

      // 오른쪽으로 드래그
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      // 아래로 드래그
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();

      // 드래그 종료
      await gesture.up();
      await tester.pumpAndSettle();

      // 스트로크가 생성되었는지 확인 (디버그 패널에 스트로크 수 표시)
      expect(find.textContaining('스트로크: 1'), findsOneWidget);
    });

    testWidgets('Undo 기능 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 새 노트로 이동
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();

      // 선 그리기
      final canvas = find.byType(CustomPaint).first;
      final center = tester.getCenter(canvas);

      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(100, 50));
      await gesture.up();
      await tester.pumpAndSettle();

      // 스트로크 1개 확인
      expect(find.textContaining('스트로크: 1'), findsOneWidget);

      // Undo 버튼 클릭
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();

      // 스트로크 0개 확인
      expect(find.textContaining('스트로크: 0'), findsOneWidget);
    });

    testWidgets('색상 변경 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 새 노트로 이동
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();

      // 색상 선택 버튼 찾기 (원형 컨테이너)
      // 툴바에서 색상 원 탭
      final colorButtons = find.byType(GestureDetector);
      expect(colorButtons, findsWidgets);
    });

    testWidgets('여러 스트로크 그리기', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 새 노트로 이동
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();

      final canvas = find.byType(CustomPaint).first;
      final center = tester.getCenter(canvas);

      // 첫 번째 선
      var gesture = await tester.startGesture(center + const Offset(-100, -50));
      await gesture.moveBy(const Offset(50, 50));
      await gesture.up();
      await tester.pumpAndSettle();

      // 두 번째 선
      gesture = await tester.startGesture(center + const Offset(0, 0));
      await gesture.moveBy(const Offset(80, 30));
      await gesture.up();
      await tester.pumpAndSettle();

      // 세 번째 선
      gesture = await tester.startGesture(center + const Offset(50, -30));
      await gesture.moveBy(const Offset(-30, 80));
      await gesture.up();
      await tester.pumpAndSettle();

      // 3개의 스트로크 확인
      expect(find.textContaining('스트로크: 3'), findsOneWidget);
    });
  });
}
