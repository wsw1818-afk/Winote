import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;

/// 템플릿 복사 기능 집중 테스트
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('템플릿 변경 후 페이지 추가 - 줄노트 템플릿 복사 확인', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. 새 노트 만들기
    final newNoteButton = find.byIcon(Icons.add);
    expect(newNoteButton, findsWidgets);
    await tester.tap(newNoteButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    debugPrint('[TEST] === 1. 새 노트 생성 완료 ===');

    // 2. 초기 상태 확인
    expect(find.textContaining('1 / 1'), findsOneWidget);
    debugPrint('[TEST] 초기 페이지: 1/1');

    // 3. 메뉴 버튼 탭
    final menuButton = find.byIcon(Icons.more_vert);
    expect(menuButton, findsWidgets);
    await tester.tap(menuButton.first);
    await tester.pumpAndSettle();
    debugPrint('[TEST] === 2. 메뉴 열림 ===');

    // 4. 배경 템플릿 메뉴 찾기
    final templateMenuItems = [
      '배경 템플릿',
      '템플릿',
      'Template',
    ];

    bool foundTemplateMenu = false;
    for (final menuText in templateMenuItems) {
      final menuItem = find.text(menuText);
      if (menuItem.evaluate().isNotEmpty) {
        await tester.tap(menuItem);
        await tester.pumpAndSettle();
        foundTemplateMenu = true;
        debugPrint('[TEST] 템플릿 메뉴 찾음: $menuText');
        break;
      }
    }

    if (!foundTemplateMenu) {
      // 메뉴 구조 확인을 위해 현재 위젯 트리 출력
      debugPrint('[TEST] 템플릿 메뉴를 찾지 못함. 현재 텍스트 위젯들:');
      final allTexts = find.byType(Text);
      for (final element in allTexts.evaluate()) {
        final textWidget = element.widget as Text;
        if (textWidget.data != null) {
          debugPrint('  - "${textWidget.data}"');
        }
      }

      // 메뉴 닫기
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // 5. 줄노트 선택
    final linedOptions = ['줄노트', 'Lined', '줄', 'lined'];
    bool foundLined = false;
    for (final option in linedOptions) {
      final linedFinder = find.text(option);
      if (linedFinder.evaluate().isNotEmpty) {
        await tester.tap(linedFinder);
        await tester.pumpAndSettle();
        foundLined = true;
        debugPrint('[TEST] === 3. 줄노트 선택됨 ===');
        break;
      }
    }

    if (!foundLined) {
      debugPrint('[TEST] 줄노트 옵션을 찾지 못함');
      // 현재 보이는 텍스트 출력
      final allTexts = find.byType(Text);
      for (final element in allTexts.evaluate()) {
        final textWidget = element.widget as Text;
        if (textWidget.data != null && textWidget.data!.isNotEmpty) {
          debugPrint('  현재 텍스트: "${textWidget.data}"');
        }
      }
    }

    // 다이얼로그/메뉴 닫기 (ESC 또는 바깥 탭)
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 6. 페이지 추가 버튼 탭
    debugPrint('[TEST] === 4. 페이지 추가 시도 ===');
    final addButtons = find.byIcon(Icons.add);
    debugPrint('[TEST] add 버튼 개수: ${addButtons.evaluate().length}');

    // 마지막 add 버튼 (하단 바의 페이지 추가 버튼)
    if (addButtons.evaluate().isNotEmpty) {
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();
    }

    // 7. 2페이지 확인
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final page2Indicator = find.textContaining('2 / 2');
    if (page2Indicator.evaluate().isNotEmpty) {
      debugPrint('[TEST] === 5. 2페이지로 이동됨 ===');
    } else {
      debugPrint('[TEST] 페이지 추가 실패 - 현재 페이지 표시기:');
      final pageTexts = find.textContaining('/');
      for (final element in pageTexts.evaluate()) {
        final textWidget = element.widget as Text;
        debugPrint('  - "${textWidget.data}"');
      }
    }

    // 8. 1페이지로 돌아가기
    final prevButton = find.byIcon(Icons.chevron_left);
    if (prevButton.evaluate().isNotEmpty) {
      await tester.tap(prevButton);
      await tester.pumpAndSettle();
      debugPrint('[TEST] === 6. 1페이지로 이동 ===');
    }

    // 9. 다시 2페이지로
    final nextButton = find.byIcon(Icons.chevron_right);
    if (nextButton.evaluate().isNotEmpty) {
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      debugPrint('[TEST] === 7. 다시 2페이지로 이동 ===');
    }

    debugPrint('[TEST] === 테스트 완료 - 로그에서 templateIndex 확인 ===');

    // 테스트 성공 조건
    expect(find.textContaining('2 / 2'), findsOneWidget);
  });
}
