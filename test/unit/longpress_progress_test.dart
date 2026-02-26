import 'package:flutter_test/flutter_test.dart';

void main() {
  group('롱프레스 진행률 계산 테스트', () {
    const int longPressDuration = 800; // ms

    test('시작 직후 진행률 0%', () {
      const elapsed = 0;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, equals(0.0));
    });

    test('절반 경과 시 진행률 50%', () {
      const elapsed = 400;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, closeTo(0.5, 0.01));
    });

    test('완료 시 진행률 100%', () {
      const elapsed = 800;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, equals(1.0));
    });

    test('초과 시간도 100%로 클램프', () {
      const elapsed = 1500; // 1.5초 경과
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, equals(1.0));
    });

    test('음수 시간은 0%로 클램프', () {
      const elapsed = -100;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, equals(0.0));
    });

    test('25% 경과 시 진행률 25%', () {
      const elapsed = 200;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, closeTo(0.25, 0.01));
    });

    test('75% 경과 시 진행률 75%', () {
      const elapsed = 600;
      final progress = (elapsed / longPressDuration).clamp(0.0, 1.0);
      expect(progress, closeTo(0.75, 0.01));
    });
  });

  group('롱프레스 원형 애니메이션 각도 계산 테스트', () {
    const double pi = 3.141592653589793;

    test('진행률 0%일 때 호 각도 0', () {
      const progress = 0.0;
      const sweepAngle = progress * 2 * pi;
      expect(sweepAngle, equals(0.0));
    });

    test('진행률 50%일 때 호 각도 π (180도)', () {
      const progress = 0.5;
      const sweepAngle = progress * 2 * pi;
      expect(sweepAngle, closeTo(pi, 0.01));
    });

    test('진행률 100%일 때 호 각도 2π (360도)', () {
      const progress = 1.0;
      const sweepAngle = progress * 2 * pi;
      expect(sweepAngle, closeTo(2 * pi, 0.01));
    });

    test('진행률 25%일 때 호 각도 π/2 (90도)', () {
      const progress = 0.25;
      const sweepAngle = progress * 2 * pi;
      expect(sweepAngle, closeTo(pi / 2, 0.01));
    });
  });

  group('DateTime 기반 경과 시간 계산 테스트', () {
    test('동일 시간 차이는 0ms', () {
      final startTime = DateTime.now();
      final elapsed = startTime.difference(startTime).inMilliseconds;
      expect(elapsed, equals(0));
    });

    test('100ms 후 경과 시간 100ms', () {
      final startTime = DateTime(2024, 1, 1, 0, 0, 0, 0);
      final currentTime = DateTime(2024, 1, 1, 0, 0, 0, 100);
      final elapsed = currentTime.difference(startTime).inMilliseconds;
      expect(elapsed, equals(100));
    });

    test('800ms 후 경과 시간 800ms', () {
      final startTime = DateTime(2024, 1, 1, 0, 0, 0, 0);
      final currentTime = DateTime(2024, 1, 1, 0, 0, 0, 800);
      final elapsed = currentTime.difference(startTime).inMilliseconds;
      expect(elapsed, equals(800));
    });
  });

  group('테이블 리사이즈 롱프레스 테스트', () {
    const int resizeLongPressDuration = 1000; // 1초
    const int visualFeedbackDelay = 500; // 0.5초

    test('0.5초 후 시각적 피드백 시작', () {
      const elapsed = 500;
      const showVisual = elapsed >= visualFeedbackDelay;
      expect(showVisual, isTrue);
    });

    test('0.3초에는 시각적 피드백 안보임', () {
      const elapsed = 300;
      const showVisual = elapsed >= visualFeedbackDelay;
      expect(showVisual, isFalse);
    });

    test('1초 후 리사이즈 활성화', () {
      const elapsed = 1000;
      const activateResize = elapsed >= resizeLongPressDuration;
      expect(activateResize, isTrue);
    });

    test('0.8초에는 리사이즈 비활성화', () {
      const elapsed = 800;
      const activateResize = elapsed >= resizeLongPressDuration;
      expect(activateResize, isFalse);
    });
  });

  group('이동 거리 기반 롱프레스 취소 테스트', () {
    const double movementThreshold = 20.0; // 20px

    double calculateDistance(double dx, double dy) {
      return (dx * dx + dy * dy).sqrt();
    }

    test('10px 이동은 롱프레스 유지', () {
      final distance = calculateDistance(6.0, 8.0); // √(36+64) = 10
      expect(distance, closeTo(10.0, 0.01));
      expect(distance < movementThreshold, isTrue);
    });

    test('25px 이동은 롱프레스 취소', () {
      final distance = calculateDistance(15.0, 20.0); // √(225+400) = 25
      expect(distance, closeTo(25.0, 0.01));
      expect(distance >= movementThreshold, isTrue);
    });

    test('정확히 20px 이동은 롱프레스 취소', () {
      final distance = calculateDistance(12.0, 16.0); // √(144+256) = 20
      expect(distance, closeTo(20.0, 0.01));
      expect(distance >= movementThreshold, isTrue);
    });

    test('0 이동은 롱프레스 유지', () {
      final distance = calculateDistance(0.0, 0.0);
      expect(distance, equals(0.0));
      expect(distance < movementThreshold, isTrue);
    });
  });
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
