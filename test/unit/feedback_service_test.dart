import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/core/services/feedback_service.dart';

/// FeedbackService 단위 테스트
void main() {
  group('FeedbackMessage 테스트', () {
    test('FeedbackMessage 기본 생성', () {
      final message = FeedbackMessage(
        message: '테스트 메시지',
        type: FeedbackType.success,
      );

      expect(message.message, equals('테스트 메시지'));
      expect(message.type, equals(FeedbackType.success));
      expect(message.timestamp, isNotNull);
      expect(message.actionLabel, isNull);
      expect(message.onAction, isNull);
      expect(message.duration, equals(const Duration(seconds: 4)));
    });

    test('FeedbackMessage 액션 포함 생성', () {
      bool actionCalled = false;
      final message = FeedbackMessage(
        message: '액션 테스트',
        type: FeedbackType.info,
        actionLabel: '실행취소',
        onAction: () => actionCalled = true,
        duration: const Duration(seconds: 5),
      );

      expect(message.actionLabel, equals('실행취소'));
      expect(message.onAction, isNotNull);
      expect(message.duration, equals(const Duration(seconds: 5)));

      // 액션 실행 테스트
      message.onAction!();
      expect(actionCalled, isTrue);
    });
  });

  group('FeedbackType 테스트', () {
    test('모든 FeedbackType 값 확인', () {
      expect(FeedbackType.values.length, equals(4));
      expect(FeedbackType.values.contains(FeedbackType.success), isTrue);
      expect(FeedbackType.values.contains(FeedbackType.error), isTrue);
      expect(FeedbackType.values.contains(FeedbackType.warning), isTrue);
      expect(FeedbackType.values.contains(FeedbackType.info), isTrue);
    });
  });

  group('FeedbackService 싱글톤 테스트', () {
    test('인스턴스가 싱글톤임을 확인', () {
      final instance1 = FeedbackService.instance;
      final instance2 = FeedbackService.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    test('초기 이력이 비어있음', () {
      final service = FeedbackService.instance;
      service.clearHistory();

      expect(service.recentFeedbacks, isEmpty);
    });
  });

  group('FeedbackService 위젯 테스트', () {
    testWidgets('showSuccess 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showSuccess(
                    context,
                    '성공 메시지',
                  );
                },
                child: const Text('성공 표시'),
              ),
            ),
          ),
        ),
      );

      // 버튼 탭
      await tester.tap(find.text('성공 표시'));
      await tester.pumpAndSettle();

      // SnackBar 표시 확인
      expect(find.text('성공 메시지'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('showError 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showError(
                    context,
                    '오류 메시지',
                  );
                },
                child: const Text('오류 표시'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('오류 표시'));
      await tester.pumpAndSettle();

      expect(find.text('오류 메시지'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('showWarning 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showWarning(
                    context,
                    '경고 메시지',
                  );
                },
                child: const Text('경고 표시'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('경고 표시'));
      await tester.pumpAndSettle();

      expect(find.text('경고 메시지'), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('showInfo 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showInfo(
                    context,
                    '정보 메시지',
                  );
                },
                child: const Text('정보 표시'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('정보 표시'));
      await tester.pumpAndSettle();

      expect(find.text('정보 메시지'), findsOneWidget);
      expect(find.byIcon(Icons.info), findsOneWidget);
    });

    testWidgets('showSaveSuccess 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showSaveSuccess(
                    context,
                    title: '테스트 노트',
                  );
                },
                child: const Text('저장 성공'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('저장 성공'));
      await tester.pumpAndSettle();

      expect(find.text('"테스트 노트" 저장됨'), findsOneWidget);
    });

    testWidgets('showSaveError 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showSaveError(
                    context,
                    error: '디스크 공간 부족',
                  );
                },
                child: const Text('저장 실패'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('저장 실패'));
      await tester.pumpAndSettle();

      expect(find.text('저장 실패: 디스크 공간 부족'), findsOneWidget);
    });

    testWidgets('showExportError 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showExportError(
                    context,
                    error: 'PDF 생성 실패',
                  );
                },
                child: const Text('내보내기 실패'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('내보내기 실패'));
      await tester.pumpAndSettle();

      expect(find.text('내보내기 실패: PDF 생성 실패'), findsOneWidget);
    });

    testWidgets('showCopySuccess 메시지 표시', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showCopySuccess(context);
                },
                child: const Text('복사'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('복사'));
      await tester.pumpAndSettle();

      expect(find.text('클립보드에 복사됨'), findsOneWidget);
    });

    testWidgets('showDeleteSuccess Undo 액션 테스트', (tester) async {
      bool undoCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showDeleteSuccess(
                    context,
                    '테스트 노트',
                    onUndo: () => undoCalled = true,
                  );
                },
                child: const Text('삭제'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(find.text('"테스트 노트" 삭제됨'), findsOneWidget);
      expect(find.text('실행취소'), findsOneWidget);

      // Undo 버튼 탭
      await tester.tap(find.text('실행취소'));
      await tester.pump();

      expect(undoCalled, isTrue);
    });

    testWidgets('showNetworkError 재시도 액션 테스트', (tester) async {
      bool retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  FeedbackService.instance.showNetworkError(
                    context,
                    onRetry: () => retryCalled = true,
                  );
                },
                child: const Text('네트워크 오류'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('네트워크 오류'));
      await tester.pumpAndSettle();

      expect(find.text('네트워크 연결을 확인해주세요'), findsOneWidget);
      expect(find.text('재시도'), findsOneWidget);

      // 재시도 버튼 탭
      await tester.tap(find.text('재시도'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets('showSyncStatus 성공/실패 테스트', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      FeedbackService.instance.showSyncStatus(context, true);
                    },
                    child: const Text('동기화 성공'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      FeedbackService.instance.showSyncStatus(context, false);
                    },
                    child: const Text('동기화 실패'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 성공 테스트
      await tester.tap(find.text('동기화 성공'));
      await tester.pumpAndSettle();
      expect(find.text('동기화 완료'), findsOneWidget);

      // 실패 테스트
      await tester.tap(find.text('동기화 실패'));
      await tester.pumpAndSettle();
      expect(find.text('동기화 실패. 나중에 다시 시도합니다.'), findsOneWidget);
    });
  });

  group('피드백 이력 테스트', () {
    testWidgets('피드백 이력 저장 확인', (tester) async {
      final service = FeedbackService.instance;
      service.clearHistory();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  service.showSuccess(context, '이력 테스트 1');
                  service.showError(context, '이력 테스트 2');
                  service.showWarning(context, '이력 테스트 3');
                },
                child: const Text('여러 피드백'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('여러 피드백'));
      await tester.pump();

      // 이력 확인 (최신 것이 앞에)
      expect(service.recentFeedbacks.length, equals(3));
      expect(service.recentFeedbacks[0].message, equals('이력 테스트 3'));
      expect(service.recentFeedbacks[1].message, equals('이력 테스트 2'));
      expect(service.recentFeedbacks[2].message, equals('이력 테스트 1'));
    });

    testWidgets('피드백 이력 초기화 확인', (tester) async {
      final service = FeedbackService.instance;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  service.showSuccess(context, '초기화 테스트');
                },
                child: const Text('피드백'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('피드백'));
      await tester.pump();

      expect(service.recentFeedbacks.isNotEmpty, isTrue);

      // 이력 초기화
      service.clearHistory();
      expect(service.recentFeedbacks, isEmpty);
    });
  });
}
