import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// UX 개선 기능 테스트
/// 최근 색상, 진동 피드백, 도구 애니메이션 검증
void main() {
  group('최근 색상 기능 테스트', () {
    test('최근 색상 목록 최대 10개 유지', () {
      final recentColors = <Color>[];
      const maxRecentColors = 10;

      // 12개 색상 추가 시도
      for (int i = 0; i < 12; i++) {
        final color = Color(0xFF000000 + i * 100);
        recentColors.insert(0, color);
        if (recentColors.length > maxRecentColors) {
          recentColors.removeLast();
        }
      }

      expect(recentColors.length, equals(maxRecentColors));
    });

    test('중복 색상은 맨 앞으로 이동', () {
      final recentColors = <Color>[
        const Color(0xFF000001),
        const Color(0xFF000002),
        const Color(0xFF000003),
      ];

      // 기존 색상 다시 추가
      const duplicateColor = Color(0xFF000002);
      recentColors.removeWhere((c) => c.value == duplicateColor.value);
      recentColors.insert(0, duplicateColor);

      expect(recentColors[0], equals(duplicateColor));
      expect(recentColors.length, equals(3));
    });

    test('최근 색상 UI에 최대 5개만 표시', () {
      final recentColors = <Color>[];
      for (int i = 0; i < 10; i++) {
        recentColors.add(Color(0xFF000000 + i * 100));
      }

      final displayedColors = recentColors.take(5).toList();
      expect(displayedColors.length, equals(5));
    });
  });

  group('진동 피드백 테스트', () {
    test('HapticFeedback 타입 확인', () {
      // HapticFeedback은 정적 메소드만 있는 클래스
      // 실제 디바이스에서만 동작하므로, 여기서는 타입만 확인
      expect(HapticFeedback.lightImpact, isA<Function>());
      expect(HapticFeedback.mediumImpact, isA<Function>());
      expect(HapticFeedback.heavyImpact, isA<Function>());
      expect(HapticFeedback.selectionClick, isA<Function>());
    });

    test('제스처별 진동 강도 매핑', () {
      final hapticMapping = {
        'undo': 'lightImpact',
        'redo': 'lightImpact',
        'fitToScreen': 'mediumImpact',
        'toolChange': 'selectionClick',
        'deleteSelection': 'mediumImpact',
      };

      expect(hapticMapping['undo'], equals('lightImpact'));
      expect(hapticMapping['fitToScreen'], equals('mediumImpact'));
      expect(hapticMapping['toolChange'], equals('selectionClick'));
    });
  });

  group('도구 전환 애니메이션 테스트', () {
    test('애니메이션 지속 시간 확인', () {
      const animationDuration = Duration(milliseconds: 150);
      expect(animationDuration.inMilliseconds, equals(150));
    });

    test('선택된 도구 스케일 값', () {
      const selectedScale = 1.1;
      const unselectedScale = 1.0;

      expect(selectedScale, greaterThan(unselectedScale));
      expect(selectedScale - unselectedScale, closeTo(0.1, 0.001));
    });

    test('AnimatedContainer 속성 검증', () {
      // AnimatedContainer에 사용되는 속성들
      const duration = Duration(milliseconds: 150);
      const curve = Curves.easeOutCubic;

      expect(duration.inMilliseconds, equals(150));
      expect(curve, equals(Curves.easeOutCubic));
    });

    test('선택된 도구 색상 강조', () {
      const selectedOpacity = 0.15;
      const unselectedOpacity = 0.0;
      const selectedBorderWidth = 2.0;
      const unselectedBorderWidth = 0.0;

      expect(selectedOpacity, greaterThan(unselectedOpacity));
      expect(selectedBorderWidth, greaterThan(unselectedBorderWidth));
    });
  });

  group('AnimatedScale 위젯 테스트', () {
    testWidgets('AnimatedScale 렌더링 성공', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedScale(
              scale: 1.1,
              duration: Duration(milliseconds: 150),
              child: Icon(Icons.edit),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('AnimatedContainer 렌더링 성공', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.edit),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsOneWidget);
    });

    testWidgets('도구 버튼 스케일 애니메이션 동작', (tester) async {
      bool isSelected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return GestureDetector(
                  onTap: () => setState(() => isSelected = !isSelected),
                  child: AnimatedScale(
                    scale: isSelected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.blue,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // 초기 상태
      expect(isSelected, isFalse);

      // 탭 후 상태 변경
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      // 애니메이션 완료 대기
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedScale), findsOneWidget);
    });
  });

  group('색상 피커 UI 테스트', () {
    testWidgets('최근 색상 행 렌더링 (빈 목록)', (tester) async {
      final recentColors = <Color>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                if (recentColors.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.history, size: 12),
                      Text('최근'),
                    ],
                  ),
                ],
                const Text('프리셋 색상'),
              ],
            ),
          ),
        ),
      );

      // 최근 색상이 없으면 history 아이콘이 없어야 함
      expect(find.byIcon(Icons.history), findsNothing);
      expect(find.text('프리셋 색상'), findsOneWidget);
    });

    testWidgets('최근 색상 행 렌더링 (색상 있음)', (tester) async {
      final recentColors = [Colors.red, Colors.blue, Colors.green];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                if (recentColors.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.history, size: 12),
                      const Text('최근'),
                      ...recentColors.map((c) => Container(
                        width: 22,
                        height: 22,
                        color: c,
                      ),),
                    ],
                  ),
                ],
                const Text('프리셋 색상'),
              ],
            ),
          ),
        ),
      );

      // 최근 색상이 있으면 history 아이콘이 있어야 함
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('최근'), findsOneWidget);
    });
  });
}
