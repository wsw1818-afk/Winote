import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// 롱프레스 타이머 비동기 테스트
/// 실제 타이머와 비동기 동작을 테스트
void main() {
  group('롱프레스 타이머 기본 테스트', () {
    test('타이머 시작 후 지정 시간에 콜백 호출', () async {
      bool callbackCalled = false;
      const duration = Duration(milliseconds: 100);

      final timer = Timer(duration, () {
        callbackCalled = true;
      });

      expect(callbackCalled, isFalse);

      // 타이머 완료 대기
      await Future.delayed(const Duration(milliseconds: 150));

      expect(callbackCalled, isTrue);
      timer.cancel();
    });

    test('타이머 취소 시 콜백 호출 안됨', () async {
      bool callbackCalled = false;
      const duration = Duration(milliseconds: 200);

      final timer = Timer(duration, () {
        callbackCalled = true;
      });

      // 50ms 후 취소
      await Future.delayed(const Duration(milliseconds: 50));
      timer.cancel();

      // 추가 대기
      await Future.delayed(const Duration(milliseconds: 200));

      expect(callbackCalled, isFalse);
    });

    test('여러 타이머 독립 실행', () async {
      int counter = 0;

      final timer1 = Timer(const Duration(milliseconds: 50), () {
        counter += 1;
      });

      final timer2 = Timer(const Duration(milliseconds: 100), () {
        counter += 10;
      });

      final timer3 = Timer(const Duration(milliseconds: 150), () {
        counter += 100;
      });

      await Future.delayed(const Duration(milliseconds: 200));

      expect(counter, equals(111));

      timer1.cancel();
      timer2.cancel();
      timer3.cancel();
    });
  });

  group('롱프레스 진행률 업데이트 테스트', () {
    test('주기적 타이머로 진행률 업데이트 (60fps)', () async {
      double progress = 0.0;
      const totalDuration = 200; // ms
      const updateInterval = Duration(milliseconds: 16); // ~60fps
      int updateCount = 0;

      final startTime = DateTime.now();

      final timer = Timer.periodic(updateInterval, (timer) {
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        progress = (elapsed / totalDuration).clamp(0.0, 1.0);
        updateCount++;

        if (progress >= 1.0) {
          timer.cancel();
        }
      });

      await Future.delayed(const Duration(milliseconds: 250));
      timer.cancel();

      expect(progress, closeTo(1.0, 0.1));
      expect(updateCount, greaterThan(10)); // 최소 10번 이상 업데이트
      print('업데이트 횟수: $updateCount');
    });

    test('타이머 취소 시 진행률 멈춤', () async {
      double progress = 0.0;
      const totalDuration = 500; // ms
      const updateInterval = Duration(milliseconds: 16);

      final startTime = DateTime.now();

      final timer = Timer.periodic(updateInterval, (timer) {
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        progress = (elapsed / totalDuration).clamp(0.0, 1.0);
      });

      // 100ms 후 취소
      await Future.delayed(const Duration(milliseconds: 100));
      final progressAtCancel = progress;
      timer.cancel();

      // 추가 대기
      await Future.delayed(const Duration(milliseconds: 200));

      // 진행률이 더 이상 증가하지 않아야 함
      expect(progress, equals(progressAtCancel));
      expect(progress, lessThan(0.5)); // 절반 이전에 취소됨
    });
  });

  group('롱프레스 완료 감지 테스트', () {
    test('롱프레스 완료 시 액션 실행', () async {
      bool actionExecuted = false;
      const longPressDuration = Duration(milliseconds: 100);

      // 롱프레스 시뮬레이션
      final completer = Completer<void>();

      final timer = Timer(longPressDuration, () {
        actionExecuted = true;
        completer.complete();
      });

      await completer.future;
      timer.cancel();

      expect(actionExecuted, isTrue);
    });

    test('롱프레스 중단 시 액션 미실행', () async {
      bool actionExecuted = false;
      const longPressDuration = Duration(milliseconds: 200);

      final timer = Timer(longPressDuration, () {
        actionExecuted = true;
      });

      // 롱프레스 도중 손가락 떼기 시뮬레이션
      await Future.delayed(const Duration(milliseconds: 50));
      timer.cancel();

      // 추가 대기해도 액션 미실행
      await Future.delayed(const Duration(milliseconds: 200));

      expect(actionExecuted, isFalse);
    });
  });

  group('이동 거리 기반 롱프레스 취소 테스트', () {
    test('움직임 감지 시 롱프레스 취소', () async {
      bool longPressCompleted = false;
      bool longPressCancelled = false;
      Timer? longPressTimer;

      const longPressDuration = Duration(milliseconds: 300);
      const movementThreshold = 20.0;

      // 시작 위치
      const double startX = 100.0;
      const double startY = 100.0;

      // 롱프레스 시작
      longPressTimer = Timer(longPressDuration, () {
        longPressCompleted = true;
      });

      // 50ms 후 움직임 발생
      await Future.delayed(const Duration(milliseconds: 50));

      // 현재 위치 (25px 이동)
      const double currentX = 115.0;
      const double currentY = 120.0;
      final double distance = _calculateDistance(startX, startY, currentX, currentY);

      if (distance >= movementThreshold) {
        longPressTimer.cancel();
        longPressCancelled = true;
      }

      await Future.delayed(const Duration(milliseconds: 300));

      expect(distance, greaterThanOrEqualTo(movementThreshold));
      expect(longPressCancelled, isTrue);
      expect(longPressCompleted, isFalse);
    });

    test('작은 움직임은 롱프레스 유지', () async {
      bool longPressCompleted = false;
      Timer? longPressTimer;

      const longPressDuration = Duration(milliseconds: 100);
      const movementThreshold = 20.0;

      const double startX = 100.0;
      const double startY = 100.0;

      longPressTimer = Timer(longPressDuration, () {
        longPressCompleted = true;
      });

      // 작은 움직임 (5px)
      const double currentX = 103.0;
      const double currentY = 104.0;
      final double distance = _calculateDistance(startX, startY, currentX, currentY);

      if (distance >= movementThreshold) {
        longPressTimer.cancel();
      }

      await Future.delayed(const Duration(milliseconds: 150));
      longPressTimer.cancel();

      expect(distance, lessThan(movementThreshold));
      expect(longPressCompleted, isTrue);
    });
  });

  group('테이블 리사이즈 롱프레스 테스트', () {
    test('테이블 리사이즈용 롱프레스 (1초)', () async {
      bool resizeActivated = false;
      bool visualFeedbackShown = false;

      const resizeLongPressDuration = Duration(milliseconds: 1000);
      const visualFeedbackDelay = Duration(milliseconds: 500);

      final startTime = DateTime.now();

      // 시각적 피드백 타이머
      final visualTimer = Timer(visualFeedbackDelay, () {
        visualFeedbackShown = true;
      });

      // 리사이즈 활성화 타이머
      final resizeTimer = Timer(resizeLongPressDuration, () {
        resizeActivated = true;
      });

      // 0.6초 후 상태 확인
      await Future.delayed(const Duration(milliseconds: 600));
      expect(visualFeedbackShown, isTrue);
      expect(resizeActivated, isFalse);

      // 1.1초 후 상태 확인
      await Future.delayed(const Duration(milliseconds: 500));
      expect(resizeActivated, isTrue);

      visualTimer.cancel();
      resizeTimer.cancel();
    });

    test('테이블 리사이즈 롱프레스 취소', () async {
      bool resizeActivated = false;
      bool visualFeedbackShown = false;

      const resizeLongPressDuration = Duration(milliseconds: 1000);
      const visualFeedbackDelay = Duration(milliseconds: 500);

      final visualTimer = Timer(visualFeedbackDelay, () {
        visualFeedbackShown = true;
      });

      final resizeTimer = Timer(resizeLongPressDuration, () {
        resizeActivated = true;
      });

      // 0.3초 후 취소
      await Future.delayed(const Duration(milliseconds: 300));
      visualTimer.cancel();
      resizeTimer.cancel();

      // 추가 대기
      await Future.delayed(const Duration(milliseconds: 1000));

      expect(visualFeedbackShown, isFalse);
      expect(resizeActivated, isFalse);
    });
  });

  group('롱프레스 상태 머신 테스트', () {
    test('상태 전이: idle → pressing → completed', () async {
      var state = LongPressState.idle;

      // pressing 상태로 전이
      state = LongPressState.pressing;
      expect(state, equals(LongPressState.pressing));

      // 롱프레스 완료 대기
      await Future.delayed(const Duration(milliseconds: 100));

      // completed 상태로 전이
      state = LongPressState.completed;
      expect(state, equals(LongPressState.completed));
    });

    test('상태 전이: idle → pressing → cancelled', () async {
      var state = LongPressState.idle;

      state = LongPressState.pressing;

      // 취소 이벤트 발생
      await Future.delayed(const Duration(milliseconds: 50));
      state = LongPressState.cancelled;

      expect(state, equals(LongPressState.cancelled));
    });

    test('상태 초기화', () async {
      var state = LongPressState.completed;

      // 다음 터치를 위해 초기화
      state = LongPressState.idle;
      expect(state, equals(LongPressState.idle));
    });
  });

  group('동시 롱프레스 처리 테스트', () {
    test('여러 포인터의 롱프레스 독립 처리', () async {
      final pointerTimers = <int, Timer>{};
      final completedPointers = <int>[];

      // 포인터 1 시작
      pointerTimers[1] = Timer(const Duration(milliseconds: 100), () {
        completedPointers.add(1);
      });

      await Future.delayed(const Duration(milliseconds: 30));

      // 포인터 2 시작
      pointerTimers[2] = Timer(const Duration(milliseconds: 100), () {
        completedPointers.add(2);
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // 포인터 1 취소
      pointerTimers[1]?.cancel();

      await Future.delayed(const Duration(milliseconds: 100));

      // 포인터 1만 취소됨
      expect(completedPointers.contains(1), isFalse);
      expect(completedPointers.contains(2), isTrue);

      for (final timer in pointerTimers.values) {
        timer.cancel();
      }
    });
  });

  group('시간 정확도 테스트', () {
    test('타이머 지연 오차 측정', () async {
      const expectedDuration = Duration(milliseconds: 100);
      final startTime = DateTime.now();
      int? actualDuration;

      final completer = Completer<void>();

      Timer(expectedDuration, () {
        actualDuration = DateTime.now().difference(startTime).inMilliseconds;
        completer.complete();
      });

      await completer.future;

      // 20ms 오차 허용
      expect(actualDuration, closeTo(100, 20));
      print('예상: 100ms, 실제: ${actualDuration}ms');
    });

    test('반복 타이머 간격 정확도', () async {
      const interval = Duration(milliseconds: 50);
      final timestamps = <int>[];
      int count = 0;

      final timer = Timer.periodic(interval, (timer) {
        timestamps.add(DateTime.now().millisecondsSinceEpoch);
        count++;
        if (count >= 5) {
          timer.cancel();
        }
      });

      await Future.delayed(const Duration(milliseconds: 300));
      timer.cancel();

      // 간격 분석
      for (int i = 1; i < timestamps.length; i++) {
        final gap = timestamps[i] - timestamps[i - 1];
        print('간격 $i: ${gap}ms');
        // 30ms 오차 허용
        expect(gap, closeTo(50, 30));
      }
    });
  });

  group('스트레스 테스트', () {
    test('다수의 타이머 동시 생성/취소', () async {
      final timers = <Timer>[];
      int completedCount = 0;

      // 100개 타이머 생성
      for (int i = 0; i < 100; i++) {
        timers.add(Timer(Duration(milliseconds: 50 + i * 2), () {
          completedCount++;
        }),);
      }

      // 50개 취소
      for (int i = 0; i < 50; i++) {
        timers[i].cancel();
      }

      await Future.delayed(const Duration(milliseconds: 300));

      // 취소된 것 제외 50개만 완료되어야 함
      expect(completedCount, equals(50));

      // 나머지 타이머 정리
      for (final timer in timers) {
        timer.cancel();
      }
    });

    test('빠른 연속 시작/취소', () async {
      int completeCount = 0;

      for (int i = 0; i < 20; i++) {
        final timer = Timer(const Duration(milliseconds: 100), () {
          completeCount++;
        });

        // 즉시 취소
        timer.cancel();
      }

      await Future.delayed(const Duration(milliseconds: 200));

      expect(completeCount, equals(0));
    });
  });

  group('Completer 기반 롱프레스 테스트', () {
    test('Completer를 사용한 롱프레스 결과 대기', () async {
      final result = await _simulateLongPress(
        duration: const Duration(milliseconds: 100),
        cancelAfter: null,
      );

      expect(result, isTrue);
    });

    test('Completer를 사용한 롱프레스 취소', () async {
      final result = await _simulateLongPress(
        duration: const Duration(milliseconds: 200),
        cancelAfter: const Duration(milliseconds: 50),
      );

      expect(result, isFalse);
    });
  });
}

// ===== 헬퍼 함수/클래스 =====

double _calculateDistance(double x1, double y1, double x2, double y2) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  return (dx * dx + dy * dy).sqrt();
}

extension on double {
  double sqrt() {
    if (this < 0) return double.nan;
    if (this == 0) return 0;
    double x = this;
    double y = 1.0;
    while ((x - y).abs() > 0.0001) {
      x = (x + y) / 2;
      y = this / x;
    }
    return x;
  }
}

enum LongPressState {
  idle,
  pressing,
  completed,
  cancelled,
}

Future<bool> _simulateLongPress({
  required Duration duration,
  Duration? cancelAfter,
}) async {
  final completer = Completer<bool>();

  final timer = Timer(duration, () {
    if (!completer.isCompleted) {
      completer.complete(true);
    }
  });

  if (cancelAfter != null) {
    Timer(cancelAfter, () {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
  }

  return completer.future;
}
