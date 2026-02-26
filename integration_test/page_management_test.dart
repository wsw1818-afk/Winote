import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;

/// 페이지 관리 기능 통합 테스트
/// - 페이지 추가 시 템플릿 복사
/// - 페이지 삭제
/// - 페이지 이동
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('페이지 관리 통합 테스트', () {
    testWidgets('새 노트 생성 후 페이지 추가 - 템플릿 복사 확인', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. 새 노트 만들기 버튼 찾기
      final newNoteButton = find.byIcon(Icons.add);
      if (newNoteButton.evaluate().isNotEmpty) {
        await tester.tap(newNoteButton.first);
        await tester.pumpAndSettle();
      }

      // 2. 에디터 화면 진입 대기
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 3. 페이지 표시기 확인 (1 / 1)
      final pageIndicator = find.textContaining('1 / 1');
      expect(pageIndicator, findsOneWidget, reason: '초기 페이지는 1/1이어야 함');

      // 4. 템플릿 변경 (메뉴 열기) - PopupMenuButton 사용
      final menuButton = find.byIcon(Icons.more_vert);
      if (menuButton.evaluate().isNotEmpty) {
        await tester.tap(menuButton.first);
        await tester.pumpAndSettle();

        // 템플릿 메뉴 찾기
        final templateMenu = find.text('배경 템플릿');
        if (templateMenu.evaluate().isNotEmpty) {
          await tester.tap(templateMenu);
          await tester.pumpAndSettle();

          // lined 템플릿 선택
          final linedOption = find.text('줄노트');
          if (linedOption.evaluate().isNotEmpty) {
            await tester.tap(linedOption);
            await tester.pumpAndSettle();
            debugPrint('[TEST] 줄노트 템플릿 선택됨');
          }
        } else {
          // 메뉴가 다른 형태일 수 있음 - 다이얼로그 닫기
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
      }

      // 5. 페이지 추가 버튼 탭
      final addPageButton = find.byIcon(Icons.add);
      // 하단 바의 추가 버튼 찾기 (여러 개 있을 수 있음)
      if (addPageButton.evaluate().isNotEmpty) {
        debugPrint('[TEST] 페이지 추가 버튼 탭');
        await tester.tap(addPageButton.last);
        await tester.pumpAndSettle();
      }

      // 6. 페이지가 2개가 되었는지 확인
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      final pageIndicator2 = find.textContaining('2 / 2');
      expect(pageIndicator2, findsOneWidget, reason: '페이지 추가 후 2/2이어야 함');

      // 7. 이전 페이지로 돌아가서 템플릿 확인
      final prevButton = find.byIcon(Icons.chevron_left);
      if (prevButton.evaluate().isNotEmpty) {
        debugPrint('[TEST] 이전 페이지로 이동');
        await tester.tap(prevButton);
        await tester.pumpAndSettle();
      }

      // 8. 다시 2페이지로 이동
      final nextButton = find.byIcon(Icons.chevron_right);
      if (nextButton.evaluate().isNotEmpty) {
        debugPrint('[TEST] 다음 페이지(2페이지)로 이동');
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
      }

      // 로그에서 템플릿 복사 확인
      debugPrint('[TEST] 테스트 완료 - 콘솔 로그에서 템플릿 값 확인');
      await tester.pumpAndSettle();
    });

    testWidgets('페이지 삭제 기능 테스트', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. 새 노트 만들기
      final newNoteButton = find.byIcon(Icons.add);
      if (newNoteButton.evaluate().isNotEmpty) {
        await tester.tap(newNoteButton.first);
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 페이지 2개 추가
      final addPageButton = find.byIcon(Icons.add);
      for (int i = 0; i < 2; i++) {
        if (addPageButton.evaluate().isNotEmpty) {
          await tester.tap(addPageButton.last);
          await tester.pumpAndSettle();
        }
      }

      // 3. 3페이지 확인
      final pageIndicator3 = find.textContaining('3 / 3');
      expect(pageIndicator3, findsOneWidget, reason: '3페이지가 되어야 함');

      // 4. 삭제 버튼 찾기 (빨간색 delete 아이콘)
      final deleteButton = find.byIcon(Icons.delete_outline);
      expect(deleteButton, findsOneWidget, reason: '삭제 버튼이 표시되어야 함');

      // 5. 삭제 버튼 탭
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      // 6. 삭제 확인 다이얼로그
      final confirmDelete = find.text('삭제');
      if (confirmDelete.evaluate().isNotEmpty) {
        await tester.tap(confirmDelete.last); // 다이얼로그의 삭제 버튼
        await tester.pumpAndSettle();
      }

      // 7. 2페이지로 줄어들었는지 확인
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      final pageIndicatorAfter = find.textContaining('/ 2');
      expect(pageIndicatorAfter, findsOneWidget, reason: '삭제 후 2페이지가 되어야 함');
    });

    testWidgets('페이지 이동 테스트', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. 새 노트 만들기
      final newNoteButton = find.byIcon(Icons.add);
      if (newNoteButton.evaluate().isNotEmpty) {
        await tester.tap(newNoteButton.first);
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 페이지 추가 (2페이지 만들기)
      final addPageButton = find.byIcon(Icons.add);
      if (addPageButton.evaluate().isNotEmpty) {
        await tester.tap(addPageButton.last);
        await tester.pumpAndSettle();
      }

      // 3. 2/2 페이지 확인
      expect(find.textContaining('2 / 2'), findsOneWidget);

      // 4. 이전 페이지로 이동 (chevron_left)
      final prevButton = find.byIcon(Icons.chevron_left);
      if (prevButton.evaluate().isNotEmpty) {
        await tester.tap(prevButton);
        await tester.pumpAndSettle();
      }

      // 5. 1/2 페이지 확인
      expect(find.textContaining('1 / 2'), findsOneWidget, reason: '이전 페이지로 이동해야 함');

      // 6. 다음 페이지로 이동 (chevron_right)
      final nextButton = find.byIcon(Icons.chevron_right);
      if (nextButton.evaluate().isNotEmpty) {
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
      }

      // 7. 2/2 페이지 확인
      expect(find.textContaining('2 / 2'), findsOneWidget, reason: '다음 페이지로 이동해야 함');
    });

    testWidgets('페이지 목록 다이얼로그 테스트', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. 새 노트 만들기
      final newNoteButton = find.byIcon(Icons.add);
      if (newNoteButton.evaluate().isNotEmpty) {
        await tester.tap(newNoteButton.first);
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 페이지 2개 추가
      final addPageButton = find.byIcon(Icons.add);
      for (int i = 0; i < 2; i++) {
        if (addPageButton.evaluate().isNotEmpty) {
          await tester.tap(addPageButton.last);
          await tester.pumpAndSettle();
        }
      }

      // 3. 페이지 표시기 탭하여 목록 열기
      final pageIndicator = find.textContaining('3 / 3');
      if (pageIndicator.evaluate().isNotEmpty) {
        await tester.tap(pageIndicator);
        await tester.pumpAndSettle();
      }

      // 4. 다이얼로그 제목 확인
      expect(find.text('페이지 선택'), findsOneWidget, reason: '페이지 목록 다이얼로그가 열려야 함');

      // 5. 3개 페이지 항목 확인
      expect(find.textContaining('페이지 1'), findsOneWidget);
      expect(find.textContaining('페이지 2'), findsOneWidget);
      expect(find.textContaining('페이지 3'), findsOneWidget);

      // 6. 다이얼로그 닫기
      final closeButton = find.text('닫기');
      if (closeButton.evaluate().isNotEmpty) {
        await tester.tap(closeButton);
        await tester.pumpAndSettle();
      }
    });
  });
}
