import 'dart:math' as math;
import '../../domain/entities/stroke_point.dart';

/// 필기 보정 강도
enum SmoothingLevel {
  none,    // 보정 없음
  light,   // 약하게 (빠른 필기용)
  medium,  // 중간 (기본값)
  strong,  // 강하게 (악필 교정)
}

/// 스트로크 스무딩 서비스 (개선 버전)
/// - 속도 기반 적응형 스무딩
/// - 베지어 커브 피팅
/// - 필압 감도 보정
/// - 떨림 제거 (Jitter removal)
/// - 펜 예측 알고리즘 (지연 감소)
/// - 입필/출필 자연스러운 처리
/// - 빠른 필기 시 포인트 보간
class StrokeSmoothingService {
  static final StrokeSmoothingService instance = StrokeSmoothingService._();
  StrokeSmoothingService._();

  /// 현재 보정 강도
  SmoothingLevel _level = SmoothingLevel.medium;
  SmoothingLevel get level => _level;
  set level(SmoothingLevel value) => _level = value;

  /// 펜 예측 활성화 여부
  bool _predictionEnabled = true;
  bool get predictionEnabled => _predictionEnabled;
  set predictionEnabled(bool value) => _predictionEnabled = value;

  /// 속도 추적을 위한 버퍼
  final List<_VelocityPoint> _velocityBuffer = [];
  static const int _velocityBufferSize = 5;

  /// 예측을 위한 최근 포인트 버퍼
  final List<StrokePoint> _predictionBuffer = [];
  static const int _predictionBufferSize = 4;

  /// 보정 강도별 파라미터
  Map<SmoothingLevel, _SmoothingParams> get _params => {
    SmoothingLevel.none: _SmoothingParams(
      minDistance: 0,
      smoothingFactor: 0,
      jitterThreshold: 0,
      cornerThreshold: 0,
      velocitySmoothing: 0,
      pressureSensitivity: 1.0,
    ),
    SmoothingLevel.light: _SmoothingParams(
      minDistance: 1.0,
      smoothingFactor: 0.15,
      jitterThreshold: 1.5,
      cornerThreshold: 50,
      velocitySmoothing: 0.2,
      pressureSensitivity: 0.9,
    ),
    SmoothingLevel.medium: _SmoothingParams(
      minDistance: 1.5,
      smoothingFactor: 0.25,
      jitterThreshold: 2.5,
      cornerThreshold: 40,
      velocitySmoothing: 0.35,
      pressureSensitivity: 0.8,
    ),
    SmoothingLevel.strong: _SmoothingParams(
      minDistance: 2.0,
      smoothingFactor: 0.4,
      jitterThreshold: 4.0,
      cornerThreshold: 30,
      velocitySmoothing: 0.5,
      pressureSensitivity: 0.7,
    ),
  };

  /// 스트로크 시작 시 버퍼 초기화
  void beginStroke() {
    _velocityBuffer.clear();
    _predictionBuffer.clear();
  }

  /// 실시간 포인트 필터링 (입력 시점에 적용)
  /// 속도 기반 적응형 스무딩 적용
  StrokePoint? filterPoint(StrokePoint newPoint, List<StrokePoint> existingPoints) {
    if (_level == SmoothingLevel.none) return newPoint;

    final params = _params[_level]!;

    // 첫 번째 포인트는 그대로 반환
    if (existingPoints.isEmpty) {
      _addToVelocityBuffer(newPoint, 0);
      return newPoint;
    }

    final lastPoint = existingPoints.last;
    final distance = _distance(newPoint, lastPoint);

    // 최소 거리 미만이면 무시 (떨림 제거)
    if (distance < params.minDistance) {
      return null;
    }

    // 속도 계산
    final timeDelta = newPoint.timestamp - lastPoint.timestamp;
    final velocity = timeDelta > 0 ? distance / timeDelta * 1000 : 0.0; // px/sec
    _addToVelocityBuffer(newPoint, velocity);

    // 평균 속도 계산
    final avgVelocity = _getAverageVelocity();

    // 속도 기반 적응형 스무딩 계수 계산
    // 빠른 속도 = 적은 스무딩, 느린 속도 = 많은 스무딩
    final adaptiveFactor = _calculateAdaptiveSmoothingFactor(
      avgVelocity,
      params.smoothingFactor,
      params.velocitySmoothing,
    );

    // Jitter threshold: 너무 가까운 포인트는 방향 변화 확인
    if (distance < params.jitterThreshold && existingPoints.length >= 2) {
      final prevPoint = existingPoints[existingPoints.length - 2];
      final angle = _angleBetween(prevPoint, lastPoint, newPoint);

      // 급격한 방향 변화(코너)가 아니면 강한 스무딩
      if (angle > params.cornerThreshold) {
        return _smoothPointAdaptive(newPoint, existingPoints, adaptiveFactor * 1.5, params);
      }
    }

    // 스무딩 적용
    return _smoothPointAdaptive(newPoint, existingPoints, adaptiveFactor, params);
  }

  /// 속도 버퍼에 추가
  void _addToVelocityBuffer(StrokePoint point, double velocity) {
    _velocityBuffer.add(_VelocityPoint(point, velocity));
    if (_velocityBuffer.length > _velocityBufferSize) {
      _velocityBuffer.removeAt(0);
    }
  }

  /// 평균 속도 계산
  double _getAverageVelocity() {
    if (_velocityBuffer.isEmpty) return 0;
    final sum = _velocityBuffer.fold<double>(0, (sum, vp) => sum + vp.velocity);
    return sum / _velocityBuffer.length;
  }

  /// 적응형 스무딩 계수 계산
  double _calculateAdaptiveSmoothingFactor(
    double velocity,
    double baseFactor,
    double velocitySensitivity,
  ) {
    // 속도 정규화 (0~1500 px/sec 범위를 0~1로)
    final normalizedVelocity = (velocity / 1500).clamp(0.0, 1.0);

    // 빠른 필기 = 적은 스무딩 (반응성 유지)
    // 느린 필기 = 많은 스무딩 (떨림 제거)
    final velocityMultiplier = 1.0 - (normalizedVelocity * velocitySensitivity);

    return (baseFactor * velocityMultiplier).clamp(0.05, 0.6);
  }

  /// 적응형 포인트 스무딩
  StrokePoint _smoothPointAdaptive(
    StrokePoint newPoint,
    List<StrokePoint> existing,
    double factor,
    _SmoothingParams params,
  ) {
    if (existing.isEmpty || factor == 0) return newPoint;

    final lastPoint = existing.last;

    // Quadratic smoothing for better curve quality
    double smoothedX, smoothedY;

    if (existing.length >= 2) {
      // 3점 가중 평균 (더 부드러운 곡선)
      final prevPoint = existing[existing.length - 2];
      final weight1 = 0.15 * factor; // 이전 포인트 가중치
      final weight2 = 0.35 * factor; // 마지막 포인트 가중치
      final weight3 = 1.0 - weight1 - weight2; // 새 포인트 가중치

      smoothedX = prevPoint.x * weight1 + lastPoint.x * weight2 + newPoint.x * weight3;
      smoothedY = prevPoint.y * weight1 + lastPoint.y * weight2 + newPoint.y * weight3;
    } else {
      // 2점 선형 보간
      smoothedX = lastPoint.x + (newPoint.x - lastPoint.x) * (1 - factor);
      smoothedY = lastPoint.y + (newPoint.y - lastPoint.y) * (1 - factor);
    }

    // 필압 스무딩 (덜 민감하게)
    final smoothedPressure = _smoothPressure(
      newPoint.pressure,
      existing,
      params.pressureSensitivity,
    );

    return StrokePoint(
      x: smoothedX,
      y: smoothedY,
      pressure: smoothedPressure,
      tilt: newPoint.tilt,
      timestamp: newPoint.timestamp,
    );
  }

  /// 필압 스무딩
  double _smoothPressure(double newPressure, List<StrokePoint> existing, double sensitivity) {
    if (existing.isEmpty) return newPressure;

    // 최근 3개 포인트의 필압 평균
    final count = math.min(3, existing.length);
    double sum = newPressure;
    for (int i = 0; i < count; i++) {
      sum += existing[existing.length - 1 - i].pressure;
    }
    final avgPressure = sum / (count + 1);

    // 감도에 따라 원본과 평균 사이 보간
    return newPressure * sensitivity + avgPressure * (1 - sensitivity);
  }

  // ==================== 펜 예측 알고리즘 ====================

  /// 다음 포인트 예측 (지연 감소용)
  /// 최근 포인트들의 속도와 가속도를 분석하여 다음 위치 예측
  StrokePoint? predictNextPoint(StrokePoint currentPoint, List<StrokePoint> existingPoints) {
    if (!_predictionEnabled || _level == SmoothingLevel.none) return null;
    if (existingPoints.length < 3) return null;

    // 예측 버퍼 업데이트
    _predictionBuffer.add(currentPoint);
    if (_predictionBuffer.length > _predictionBufferSize) {
      _predictionBuffer.removeAt(0);
    }

    if (_predictionBuffer.length < 3) return null;

    // 최근 3개 포인트로 속도/가속도 계산
    final p0 = _predictionBuffer[_predictionBuffer.length - 3];
    final p1 = _predictionBuffer[_predictionBuffer.length - 2];
    final p2 = _predictionBuffer[_predictionBuffer.length - 1];

    // 속도 벡터 계산
    final dt1 = (p1.timestamp - p0.timestamp).toDouble();
    final dt2 = (p2.timestamp - p1.timestamp).toDouble();

    // Division by zero 방지: 최소 1ms 이상 필요
    if (dt1 < 1 || dt2 < 1) return null;

    final vx1 = (p1.x - p0.x) / dt1;
    final vy1 = (p1.y - p0.y) / dt1;
    final vx2 = (p2.x - p1.x) / dt2;
    final vy2 = (p2.y - p1.y) / dt2;

    // 가속도 계산 (dt 합이 0이 될 수 없음 - 위에서 최소 1ms 보장)
    final avgDt = (dt1 + dt2) / 2;
    final ax = (vx2 - vx1) / avgDt;
    final ay = (vy2 - vy1) / avgDt;

    // 예측 시간 (속도에 따라 조절 - 빠를수록 더 앞을 예측)
    final velocity = math.sqrt(vx2 * vx2 + vy2 * vy2);
    final predictionTime = (velocity * 0.02).clamp(5.0, 20.0); // 5~20ms 앞 예측

    // 2차 운동 방정식으로 위치 예측: x = x0 + v*t + 0.5*a*t^2
    final predictedX = p2.x + vx2 * predictionTime + 0.5 * ax * predictionTime * predictionTime;
    final predictedY = p2.y + vy2 * predictionTime + 0.5 * ay * predictionTime * predictionTime;

    // 예측 거리 제한 (너무 멀리 예측하지 않음)
    const maxPredictionDist = 15.0; // 최대 15px
    final dx = predictedX - p2.x;
    final dy = predictedY - p2.y;
    final dist = math.sqrt(dx * dx + dy * dy);

    double finalX = predictedX;
    double finalY = predictedY;

    if (dist > maxPredictionDist) {
      final scale = maxPredictionDist / dist;
      finalX = p2.x + dx * scale;
      finalY = p2.y + dy * scale;
    }

    return StrokePoint(
      x: finalX,
      y: finalY,
      pressure: p2.pressure, // 필압은 현재값 유지
      tilt: p2.tilt,
      timestamp: p2.timestamp + predictionTime.round(),
    );
  }

  // ==================== 빠른 필기 시 포인트 보간 ====================

  /// 두 포인트 사이에 보간 포인트 생성 (빠른 필기 시 끊김 방지)
  List<StrokePoint> interpolatePoints(StrokePoint p1, StrokePoint p2, {double maxGap = 8.0}) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final distance = math.sqrt(dx * dx + dy * dy);

    // 거리가 maxGap 이하면 보간 불필요
    if (distance <= maxGap) {
      return [p2];
    }

    // 필요한 보간 포인트 수 계산
    final numPoints = (distance / maxGap).ceil();
    final result = <StrokePoint>[];

    for (int i = 1; i <= numPoints; i++) {
      final t = i / numPoints;

      // Hermite 보간으로 더 자연스러운 곡선 (속도 기반)
      final x = p1.x + dx * t;
      final y = p1.y + dy * t;

      // 필압은 선형 보간
      final pressure = p1.pressure + (p2.pressure - p1.pressure) * t;

      // 타임스탬프 보간
      final timestamp = p1.timestamp + ((p2.timestamp - p1.timestamp) * t).round();

      result.add(StrokePoint(
        x: x,
        y: y,
        pressure: pressure,
        tilt: p1.tilt + (p2.tilt - p1.tilt) * t,
        timestamp: timestamp,
      ),);
    }

    return result;
  }

  // ==================== 입필/출필 처리 ====================

  /// 스트로크 시작부 자연스러운 처리 (입필 효과)
  /// 처음 몇 포인트의 필압을 점진적으로 증가
  List<StrokePoint> applyEntryTaper(List<StrokePoint> points, {int taperLength = 5}) {
    if (points.length <= taperLength) return points;

    final result = <StrokePoint>[];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      double pressure = p.pressure;

      if (i < taperLength) {
        // 부드러운 이징 곡선 (ease-in)
        final t = (i + 1) / taperLength;
        final easedT = t * t * (3 - 2 * t); // smoothstep
        pressure = p.pressure * (0.2 + easedT * 0.8); // 20%에서 시작
      }

      result.add(StrokePoint(
        x: p.x,
        y: p.y,
        pressure: pressure,
        tilt: p.tilt,
        timestamp: p.timestamp,
      ),);
    }
    return result;
  }

  /// 스트로크 끝부분 자연스러운 처리 (출필 효과)
  /// 마지막 몇 포인트의 필압을 점진적으로 감소
  List<StrokePoint> applyExitTaper(List<StrokePoint> points, {int taperLength = 5}) {
    if (points.length <= taperLength) return points;

    final result = List<StrokePoint>.from(points);
    final startIdx = points.length - taperLength;

    for (int i = startIdx; i < points.length; i++) {
      final p = points[i];
      final distFromEnd = points.length - 1 - i;

      // 부드러운 이징 곡선 (ease-out)
      final t = (distFromEnd + 1) / taperLength;
      final easedT = t * t * (3 - 2 * t); // smoothstep
      final pressure = p.pressure * (0.1 + easedT * 0.9); // 10%로 끝남

      result[i] = StrokePoint(
        x: p.x,
        y: p.y,
        pressure: pressure,
        tilt: p.tilt,
        timestamp: p.timestamp,
      );
    }
    return result;
  }

  /// 완성된 스트로크에 입필/출필 모두 적용
  List<StrokePoint> applyNaturalTaper(List<StrokePoint> points) {
    if (points.length < 6) return points;

    // 스트로크 길이에 따라 테이퍼 길이 조절
    final taperLength = math.min(5, points.length ~/ 4);
    if (taperLength < 2) return points;

    var result = applyEntryTaper(points, taperLength: taperLength);
    result = applyExitTaper(result, taperLength: taperLength);
    return result;
  }

  /// 완성된 스트로크 후처리
  /// Bezier 스플라인으로 부드럽게 재구성
  List<StrokePoint> smoothStroke(List<StrokePoint> points) {
    if (_level == SmoothingLevel.none || points.length < 4) {
      return points;
    }

    final params = _params[_level]!;

    // 1단계: RDP 알고리즘으로 포인트 단순화
    final simplified = _rdpSimplify(points, params.minDistance);

    if (simplified.length < 4) {
      return _movingAverageSmooth(simplified, 3);
    }

    // 2단계: Catmull-Rom 스플라인 보간
    final interpolated = _catmullRomInterpolate(simplified, 3);

    // 3단계: 최종 이동 평균 스무딩
    return _movingAverageSmooth(interpolated, _getWindowSize());
  }

  /// Catmull-Rom 스플라인 보간
  List<StrokePoint> _catmullRomInterpolate(List<StrokePoint> points, int subdivisions) {
    if (points.length < 4) return points;

    final result = <StrokePoint>[];

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[math.min(points.length - 1, i + 1)];
      final p3 = points[math.min(points.length - 1, i + 2)];

      for (int j = 0; j < subdivisions; j++) {
        final t = j / subdivisions;
        final point = _catmullRomPoint(p0, p1, p2, p3, t);
        result.add(point);
      }
    }

    // 마지막 포인트 추가
    result.add(points.last);

    return result;
  }

  /// Catmull-Rom 포인트 계산
  StrokePoint _catmullRomPoint(
    StrokePoint p0,
    StrokePoint p1,
    StrokePoint p2,
    StrokePoint p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;

    // Catmull-Rom 계수
    final x = 0.5 * ((2 * p1.x) +
        (-p0.x + p2.x) * t +
        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);

    final y = 0.5 * ((2 * p1.y) +
        (-p0.y + p2.y) * t +
        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);

    // 압력과 타임스탬프는 선형 보간
    final pressure = p1.pressure + (p2.pressure - p1.pressure) * t;
    final timestamp = (p1.timestamp + (p2.timestamp - p1.timestamp) * t).round();

    return StrokePoint(
      x: x,
      y: y,
      pressure: pressure,
      tilt: p1.tilt,
      timestamp: timestamp,
    );
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

  /// Ramer-Douglas-Peucker 알고리즘 (점 단순화) - 반복적 구현
  List<StrokePoint> _rdpSimplify(List<StrokePoint> points, double epsilon) {
    if (points.length < 3) return List.from(points);

    // 매우 긴 스트로크는 먼저 샘플링
    final workingPoints = points.length > 500
        ? _samplePoints(points, 500)
        : points;

    final keepIndices = <int>{0, workingPoints.length - 1};
    final stack = <(int, int)>[(0, workingPoints.length - 1)];

    while (stack.isNotEmpty) {
      final (startIdx, endIdx) = stack.removeLast();

      if (endIdx - startIdx < 2) continue;

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

      if (maxDistance > epsilon) {
        keepIndices.add(maxIndex);
        stack.add((startIdx, maxIndex));
        stack.add((maxIndex, endIdx));
      }
    }

    final sortedIndices = keepIndices.toList()..sort();
    return sortedIndices.map((i) => workingPoints[i]).toList();
  }

  /// 포인트 샘플링
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
      // 시작과 끝 부분은 그대로 유지
      if (i < halfWindow || i >= points.length - halfWindow) {
        result.add(points[i]);
        continue;
      }

      // 가우시안 가중 평균 (중심에 높은 가중치)
      double sumX = 0, sumY = 0, sumPressure = 0, totalWeight = 0;

      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j >= 0 && j < points.length) {
          // 가우시안 가중치
          final distance = (j - i).abs();
          final weight = math.exp(-distance * distance / (2 * halfWindow * halfWindow));

          sumX += points[j].x * weight;
          sumY += points[j].y * weight;
          sumPressure += points[j].pressure * weight;
          totalWeight += weight;
        }
      }

      result.add(StrokePoint(
        x: sumX / totalWeight,
        y: sumY / totalWeight,
        pressure: sumPressure / totalWeight,
        tilt: points[i].tilt,
        timestamp: points[i].timestamp,
      ),);
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

    // 부동소수점 안전 비교: 매우 작은 값은 0으로 간주
    const epsilon = 1e-10;
    if (mag1 < epsilon || mag2 < epsilon) return 180;

    final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }

  /// 도형 자동 인식 설정
  bool _shapeRecognitionEnabled = false;
  bool get shapeRecognitionEnabled => _shapeRecognitionEnabled;
  set shapeRecognitionEnabled(bool value) => _shapeRecognitionEnabled = value;

  /// 도형 인식이 적용된 스트로크 반환
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

  /// 직선 여부 판정
  bool _isLikelyLine(List<StrokePoint> points) {
    if (points.length < 3) return false;

    final startEnd = _distance(points.first, points.last);
    if (startEnd < 30) return false;

    // 스트로크 전체 길이 계산
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += _distance(points[i - 1], points[i]);
    }

    // 직선에서의 편차 계산
    double totalDeviation = 0;
    double maxDeviation = 0;
    for (final point in points) {
      final deviation = _perpendicularDistance(point, points.first, points.last);
      totalDeviation += deviation;
      if (deviation > maxDeviation) maxDeviation = deviation;
    }
    final avgDeviation = totalDeviation / points.length;

    // 직선 인식 조건 완화:
    // 1. 평균 편차가 시작-끝 거리의 12% 이하
    // 2. 최대 편차가 시작-끝 거리의 20% 이하
    // 3. 전체 경로 길이가 시작-끝 거리의 1.3배 이하 (너무 구불구불하지 않음)
    final avgDeviationOk = avgDeviation < startEnd * 0.12;
    final maxDeviationOk = maxDeviation < startEnd * 0.20;
    final pathLengthOk = totalLength < startEnd * 1.3;

    return avgDeviationOk && maxDeviationOk && pathLengthOk;
  }

  /// 직선으로 교정
  List<StrokePoint> _correctToLine(List<StrokePoint> points) {
    if (points.isEmpty) return points;

    final start = points.first;
    final end = points.last;

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

  /// 닫힌 도형 여부
  bool _isLikelyClosed(List<StrokePoint> points) {
    if (points.length < 8) return false;  // 최소 포인트 수 완화

    final start = points.first;
    final end = points.last;
    final distance = _distance(start, end);

    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += _distance(points[i - 1], points[i]);
    }

    // 닫힘 판정 완화: 15% -> 25%
    // 시작점과 끝점 사이 거리가 전체 경로 길이의 25% 이하면 닫힌 도형으로 판정
    return distance < totalLength * 0.25;
  }

  /// 원 여부 판정
  bool _isLikelyCircle(List<StrokePoint> points) {
    if (points.length < 8) return false;  // 최소 포인트 수 완화

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

    if (avgRadius < 15) return false;  // 최소 반지름 완화

    // 가로/세로 비율 체크 (타원도 허용)
    final width = maxX - minX;
    final height = maxY - minY;
    final aspectRatio = math.min(width, height) / math.max(width, height);
    if (aspectRatio < 0.5) return false;  // 너무 찌그러진 도형 제외

    double sumSquaredDiff = 0;
    for (final p in points) {
      final dist = math.sqrt(math.pow(p.x - centerX, 2) + math.pow(p.y - centerY, 2));
      sumSquaredDiff += math.pow(dist - avgRadius, 2);
    }
    final variance = sumSquaredDiff / points.length;
    final stdDev = math.sqrt(variance);

    // 원 인식 임계값 완화: 15% -> 25%
    return stdDev < avgRadius * 0.25;
  }

  /// 타원으로 교정
  List<StrokePoint> _correctToEllipse(List<StrokePoint> points) {
    if (points.isEmpty) return points;

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
      ),);
    }

    return result;
  }
}

/// 속도 추적용 포인트
class _VelocityPoint {
  final StrokePoint point;
  final double velocity;

  _VelocityPoint(this.point, this.velocity);
}

/// 스무딩 파라미터
class _SmoothingParams {
  final double minDistance;        // 최소 포인트 간격
  final double smoothingFactor;    // 기본 스무딩 강도 (0~1)
  final double jitterThreshold;    // 떨림 감지 임계값
  final double cornerThreshold;    // 코너 감지 각도 (도)
  final double velocitySmoothing;  // 속도 기반 스무딩 민감도
  final double pressureSensitivity; // 필압 민감도

  _SmoothingParams({
    required this.minDistance,
    required this.smoothingFactor,
    required this.jitterThreshold,
    required this.cornerThreshold,
    required this.velocitySmoothing,
    required this.pressureSensitivity,
  });
}
