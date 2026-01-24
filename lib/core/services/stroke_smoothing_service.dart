import 'dart:math' as math;
import '../../domain/entities/stroke_point.dart';

/// 필기 보정 강도
enum SmoothingLevel {
  none,    // 보정 없음
  light,   // 약하게 (빠른 필기용)
  medium,  // 중간 (기본값)
  strong,  // 강하게 (악필 교정)
}

/// 스트로크 스무딩 서비스
/// - 떨림 제거 (Jitter removal)
/// - 곡선 부드럽게 (Curve smoothing)
/// - 속도 기반 적응형 보정
class StrokeSmoothingService {
  static final StrokeSmoothingService instance = StrokeSmoothingService._();
  StrokeSmoothingService._();

  /// 현재 보정 강도
  SmoothingLevel _level = SmoothingLevel.medium;
  SmoothingLevel get level => _level;
  set level(SmoothingLevel value) => _level = value;

  /// 보정 강도별 파라미터
  Map<SmoothingLevel, _SmoothingParams> get _params => {
    SmoothingLevel.none: _SmoothingParams(
      minDistance: 0,
      smoothingFactor: 0,
      jitterThreshold: 0,
      cornerThreshold: 0,
    ),
    SmoothingLevel.light: _SmoothingParams(
      minDistance: 1.5,
      smoothingFactor: 0.2,
      jitterThreshold: 2.0,
      cornerThreshold: 60,
    ),
    SmoothingLevel.medium: _SmoothingParams(
      minDistance: 2.0,
      smoothingFactor: 0.35,
      jitterThreshold: 3.0,
      cornerThreshold: 45,
    ),
    SmoothingLevel.strong: _SmoothingParams(
      minDistance: 3.0,
      smoothingFactor: 0.5,
      jitterThreshold: 5.0,
      cornerThreshold: 30,
    ),
  };

  /// 실시간 포인트 필터링 (입력 시점에 적용)
  /// 이전 포인트와 비교하여 떨림/노이즈 제거
  StrokePoint? filterPoint(StrokePoint newPoint, List<StrokePoint> existingPoints) {
    if (_level == SmoothingLevel.none) return newPoint;

    final params = _params[_level]!;

    // 첫 번째 포인트는 그대로 반환
    if (existingPoints.isEmpty) return newPoint;

    final lastPoint = existingPoints.last;
    final distance = _distance(newPoint, lastPoint);

    // 최소 거리 미만이면 무시 (떨림 제거)
    if (distance < params.minDistance) {
      return null;
    }

    // Jitter threshold: 너무 가까운 포인트는 평균화
    if (distance < params.jitterThreshold && existingPoints.length >= 2) {
      final prevPoint = existingPoints[existingPoints.length - 2];

      // 방향 변화 감지
      final angle = _angleBetween(prevPoint, lastPoint, newPoint);

      // 급격한 방향 변화가 아니면 스무딩 적용
      if (angle > params.cornerThreshold) {
        return _smoothPoint(newPoint, existingPoints, params.smoothingFactor);
      }
    }

    // 스무딩 적용
    return _smoothPoint(newPoint, existingPoints, params.smoothingFactor);
  }

  /// 포인트 스무딩 (가중 이동 평균)
  StrokePoint _smoothPoint(StrokePoint newPoint, List<StrokePoint> existing, double factor) {
    if (existing.isEmpty || factor == 0) return newPoint;

    final lastPoint = existing.last;

    // Exponential smoothing
    final smoothedX = lastPoint.x + (newPoint.x - lastPoint.x) * (1 - factor);
    final smoothedY = lastPoint.y + (newPoint.y - lastPoint.y) * (1 - factor);

    // 필압도 약간 스무딩
    final smoothedPressure = lastPoint.pressure * factor + newPoint.pressure * (1 - factor);

    return StrokePoint(
      x: smoothedX,
      y: smoothedY,
      pressure: smoothedPressure,
      tilt: newPoint.tilt,
      timestamp: newPoint.timestamp,
    );
  }

  /// 완성된 스트로크 후처리 (선택적)
  /// Ramer-Douglas-Peucker 알고리즘으로 불필요한 포인트 제거 후
  /// Bezier 스플라인으로 부드럽게 재구성
  List<StrokePoint> smoothStroke(List<StrokePoint> points) {
    if (_level == SmoothingLevel.none || points.length < 3) {
      return points;
    }

    final params = _params[_level]!;

    // 1단계: RDP 알고리즘으로 포인트 단순화
    final simplified = _rdpSimplify(points, params.minDistance);

    // 2단계: 이동 평균 스무딩
    final smoothed = _movingAverageSmooth(simplified, _getWindowSize());

    return smoothed;
  }

  /// 보정 강도에 따른 윈도우 크기
  int _getWindowSize() {
    switch (_level) {
      case SmoothingLevel.none:
        return 1;
      case SmoothingLevel.light:
        return 3;
      case SmoothingLevel.medium:
        return 5;
      case SmoothingLevel.strong:
        return 7;
    }
  }

  /// Ramer-Douglas-Peucker 알고리즘 (점 단순화) - 반복적 구현으로 스택 오버플로우 방지 및 성능 개선
  List<StrokePoint> _rdpSimplify(List<StrokePoint> points, double epsilon) {
    if (points.length < 3) return List.from(points);

    // 매우 긴 스트로크는 먼저 샘플링하여 처리 시간 단축
    final workingPoints = points.length > 500
        ? _samplePoints(points, 500)
        : points;

    // 결과에 포함할 인덱스를 저장할 Set (중복 방지)
    final keepIndices = <int>{0, workingPoints.length - 1};

    // 처리할 구간을 저장할 스택 (시작 인덱스, 끝 인덱스)
    final stack = <(int, int)>[(0, workingPoints.length - 1)];

    while (stack.isNotEmpty) {
      final (startIdx, endIdx) = stack.removeLast();

      if (endIdx - startIdx < 2) continue;

      // 가장 먼 점 찾기
      double maxDistance = 0;
      int maxIndex = startIdx;

      final start = workingPoints[startIdx];
      final end = workingPoints[endIdx];

      for (int i = startIdx + 1; i < endIdx; i++) {
        final d = _perpendicularDistance(workingPoints[i], start, end);
        if (d > maxDistance) {
          maxDistance = d;
          maxIndex = i;
        }
      }

      // 임계값보다 크면 해당 점을 유지하고 양쪽 구간을 스택에 추가
      if (maxDistance > epsilon) {
        keepIndices.add(maxIndex);
        stack.add((startIdx, maxIndex));
        stack.add((maxIndex, endIdx));
      }
    }

    // 정렬된 인덱스 순서로 포인트 추출
    final sortedIndices = keepIndices.toList()..sort();
    return sortedIndices.map((i) => workingPoints[i]).toList();
  }

  /// 포인트 샘플링 (매우 긴 스트로크 처리 최적화)
  List<StrokePoint> _samplePoints(List<StrokePoint> points, int targetCount) {
    if (points.length <= targetCount) return points;

    final result = <StrokePoint>[points.first];
    final step = (points.length - 1) / (targetCount - 1);

    for (int i = 1; i < targetCount - 1; i++) {
      final index = (i * step).round();
      if (index < points.length) {
        result.add(points[index]);
      }
    }

    result.add(points.last);
    return result;
  }

  /// 점에서 선분까지의 수직 거리
  double _perpendicularDistance(StrokePoint point, StrokePoint lineStart, StrokePoint lineEnd) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;

    if (dx == 0 && dy == 0) {
      return _distance(point, lineStart);
    }

    final t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx * dx + dy * dy);
    final clampedT = t.clamp(0.0, 1.0);

    final projX = lineStart.x + clampedT * dx;
    final projY = lineStart.y + clampedT * dy;

    return math.sqrt(math.pow(point.x - projX, 2) + math.pow(point.y - projY, 2));
  }

  /// 이동 평균 스무딩
  List<StrokePoint> _movingAverageSmooth(List<StrokePoint> points, int windowSize) {
    if (points.length < windowSize || windowSize < 2) {
      return points;
    }

    final result = <StrokePoint>[];
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < points.length; i++) {
      // 시작과 끝 부분은 그대로 유지 (필기 시작/끝점 보존)
      if (i < halfWindow || i >= points.length - halfWindow) {
        result.add(points[i]);
        continue;
      }

      // 윈도우 내 평균 계산
      double sumX = 0, sumY = 0, sumPressure = 0;
      int count = 0;

      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j >= 0 && j < points.length) {
          sumX += points[j].x;
          sumY += points[j].y;
          sumPressure += points[j].pressure;
          count++;
        }
      }

      result.add(StrokePoint(
        x: sumX / count,
        y: sumY / count,
        pressure: sumPressure / count,
        tilt: points[i].tilt,
        timestamp: points[i].timestamp,
      ));
    }

    return result;
  }

  /// 두 점 사이 거리
  double _distance(StrokePoint a, StrokePoint b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

  /// 세 점 사이 각도 (도 단위)
  double _angleBetween(StrokePoint a, StrokePoint b, StrokePoint c) {
    final v1x = a.x - b.x;
    final v1y = a.y - b.y;
    final v2x = c.x - b.x;
    final v2y = c.y - b.y;

    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 180;

    final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }

  /// 도형 자동 인식 설정
  bool _shapeRecognitionEnabled = false;
  bool get shapeRecognitionEnabled => _shapeRecognitionEnabled;
  set shapeRecognitionEnabled(bool value) => _shapeRecognitionEnabled = value;

  /// 도형 인식이 적용된 스트로크 반환 (직선/원 자동 교정)
  /// 원본 스트로크와 인식된 도형 타입을 함께 반환
  (List<StrokePoint>, String?) recognizeAndCorrectShape(List<StrokePoint> points) {
    if (!_shapeRecognitionEnabled || points.length < 5) {
      return (points, null);
    }

    // 직선 인식 체크
    if (_isLikelyLine(points)) {
      return (_correctToLine(points), 'line');
    }

    // 원/타원 인식 체크
    if (_isLikelyClosed(points) && _isLikelyCircle(points)) {
      return (_correctToEllipse(points), 'circle');
    }

    return (points, null);
  }

  /// 직선 여부 판정 (선형 회귀로 R² 계산)
  bool _isLikelyLine(List<StrokePoint> points) {
    if (points.length < 3) return false;

    // 시작점과 끝점 거리
    final startEnd = _distance(points.first, points.last);
    if (startEnd < 30) return false; // 너무 짧은 스트로크는 제외

    // 모든 포인트의 직선으로부터의 평균 거리 계산
    double totalDeviation = 0;
    for (final point in points) {
      totalDeviation += _perpendicularDistance(point, points.first, points.last);
    }
    final avgDeviation = totalDeviation / points.length;

    // 평균 편차가 선 길이의 5% 이하면 직선으로 인식
    return avgDeviation < startEnd * 0.05;
  }

  /// 직선으로 교정
  List<StrokePoint> _correctToLine(List<StrokePoint> points) {
    if (points.isEmpty) return points;

    final start = points.first;
    final end = points.last;

    // 시작점과 끝점만 유지 (직선)
    return [
      start,
      StrokePoint(
        x: end.x,
        y: end.y,
        pressure: end.pressure,
        tilt: end.tilt,
        timestamp: end.timestamp,
      ),
    ];
  }

  /// 닫힌 도형 여부 (시작점과 끝점이 가까움)
  bool _isLikelyClosed(List<StrokePoint> points) {
    if (points.length < 10) return false;

    final start = points.first;
    final end = points.last;
    final distance = _distance(start, end);

    // 전체 경로 길이 계산
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += _distance(points[i - 1], points[i]);
    }

    // 시작-끝 거리가 전체 길이의 15% 이하면 닫힌 도형
    return distance < totalLength * 0.15;
  }

  /// 원 여부 판정 (중심점으로부터의 거리 분산 체크)
  bool _isLikelyCircle(List<StrokePoint> points) {
    if (points.length < 10) return false;

    // 바운딩 박스로 중심점 계산
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final avgRadius = ((maxX - minX) + (maxY - minY)) / 4;

    if (avgRadius < 20) return false; // 너무 작은 원은 제외

    // 각 포인트의 중심으로부터의 거리 분산 계산
    double sumSquaredDiff = 0;
    for (final p in points) {
      final dist = math.sqrt(math.pow(p.x - centerX, 2) + math.pow(p.y - centerY, 2));
      sumSquaredDiff += math.pow(dist - avgRadius, 2);
    }
    final variance = sumSquaredDiff / points.length;
    final stdDev = math.sqrt(variance);

    // 표준편차가 평균 반지름의 15% 이하면 원으로 인식
    return stdDev < avgRadius * 0.15;
  }

  /// 타원으로 교정
  List<StrokePoint> _correctToEllipse(List<StrokePoint> points) {
    if (points.isEmpty) return points;

    // 바운딩 박스로 타원 파라미터 계산
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final radiusX = (maxX - minX) / 2;
    final radiusY = (maxY - minY) / 2;

    // 타원 위의 점들 생성 (36개 포인트)
    final result = <StrokePoint>[];
    final avgPressure = points.map((p) => p.pressure).reduce((a, b) => a + b) / points.length;

    for (int i = 0; i <= 36; i++) {
      final angle = (i / 36) * 2 * math.pi;
      result.add(StrokePoint(
        x: centerX + radiusX * math.cos(angle),
        y: centerY + radiusY * math.sin(angle),
        pressure: avgPressure,
        tilt: 0,
        timestamp: points.first.timestamp + i,
      ));
    }

    return result;
  }
}

/// 스무딩 파라미터
class _SmoothingParams {
  final double minDistance;      // 최소 포인트 간격
  final double smoothingFactor;  // 스무딩 강도 (0~1)
  final double jitterThreshold;  // 떨림 감지 임계값
  final double cornerThreshold;  // 코너 감지 각도 (도)

  _SmoothingParams({
    required this.minDistance,
    required this.smoothingFactor,
    required this.jitterThreshold,
    required this.cornerThreshold,
  });
}
