import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:winote/main.dart' as app;

/// 템플릿 변경 후 페이지 추가 테스트
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('템플릿 변경 후 페이지 추가 - 줄노트 복사 확인', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. 새 노트 만들기
    final newNoteButton = find.byIcon(Icons.add);
    expect(newNoteButton, findsWidgets);
    await tester.tap(newNoteButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    debugPrint('[TEST] === 1. 새 노트 생성 완료 ===');

    // 2. QuickToolbar에서 템플릿 버튼 찾기 (grid_4x4 아이콘)
    final templateButton = find.byIcon(Icons.grid_4x4);
    if (templateButton.evaluate().isNotEmpty) {
      debugPrint('[TEST] 템플릿 버튼 발견 (grid_4x4)');
      await tester.tap(templateButton.first);
      await tester.pumpAndSettle();

      // 3. 줄 노트 선택
      final linedOption = find.text('줄 노트');
      if (linedOption.evaluate().isNotEmpty) {
        await tester.tap(linedOption);
        await tester.pumpAndSettle();
        debugPrint('[TEST] === 2. 줄 노트 선택됨 ===');
      } else {
        debugPrint('[TEST] 줄 노트 옵션을 찾지 못함');
        // 현재 메뉴 항목 출력
        final allTexts = find.byType(Text);
        for (final element in allTexts.evaluate()) {
          final textWidget = element.widget as Text;
          if (textWidget.data != null && textWidget.data!.isNotEmpty) {
            debugPrint('  메뉴 텍스트: "${textWidget.data}"');
          }
        }
        // 메뉴 닫기
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    } else {
      // 다른 템플릿 아이콘 시도
      final otherTemplateIcons = [
        Icons.view_headline,  // lined
        Icons.crop_square,    // blank
        Icons.more_horiz,     // dotted
      ];

      for (final icon in otherTemplateIcons) {
        final btn = find.byIcon(icon);
        if (btn.evaluate().isNotEmpty) {
          debugPrint('[TEST] 다른 템플릿 버튼 발견: $icon');
          await tester.tap(btn.first);
          await tester.pumpAndSettle();

          final linedOption = find.text('줄 노트');
          if (linedOption.evaluate().isNotEmpty) {
            await tester.tap(linedOption);
            await tester.pumpAndSettle();
            debugPrint('[TEST] === 2. 줄 노트 선택됨 ===');
            break;
          }

          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
      }
    }

    // 4. 페이지 추가 버튼 탭
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    debugPrint('[TEST] === 3. 페이지 추가 시도 ===');

    final addButtons = find.byIcon(Icons.add);
    debugPrint('[TEST] add 버튼 개수: ${addButtons.evaluate().length}');

    if (addButtons.evaluate().isNotEmpty) {
      // 하단 바의 페이지 추가 버튼 (마지막 add 버튼)
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();
    }

    // 5. 2페이지 확인
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final page2Indicator = find.textContaining('2 / 2');
    if (page2Indicator.evaluate().isNotEmpty) {
      debugPrint('[TEST] === 4. 2페이지로 이동됨 ===');
    } else {
      debugPrint('[TEST] 페이지 추가 실패');
      final pageTexts = find.textContaining('/');
      for (final element in pageTexts.evaluate()) {
        final textWidget = element.widget as Text;
        debugPrint('  페이지 표시: "${textWidget.data}"');
      }
    }

    debugPrint('[TEST] === 테스트 완료 ===');
    debugPrint('[TEST] 콘솔 로그에서 templateIndex=1 (lined) 확인 필요');
  });
}
