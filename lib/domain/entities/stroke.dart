import 'dart:ui';

import 'stroke_point.dart';
import 'bounding_box.dart';

/// 필기 도구 타입
enum ToolType {
  pen,        // 기본 펜
  pencil,     // 연필
  marker,     // 마커
  highlighter, // 형광펜
  eraser,     // 지우개
}

/// 도형 종류 (isShape가 true일 때 사용)
enum ShapeType {
  none,       // 일반 스트로크 (도형 아님)
  line,       // 직선
  rectangle,  // 사각형
  circle,     // 원/타원
  arrow,      // 화살표
}

/// 스트로크 (펜 획)
class Stroke {
  final String id;
  final ToolType toolType;
  final Color color;
  final double width;
  final List<StrokePoint> points;
  BoundingBox boundingBox;
  final int timestamp;
  final bool isShape; // 도형인 경우 true (직선으로만 그림)
  final ShapeType shapeType; // 도형 종류

  Stroke({
    required this.id,
    required this.toolType,
    required this.color,
    required this.width,
    required this.points,
    BoundingBox? boundingBox,
    required this.timestamp,
    this.isShape = false,
    this.shapeType = ShapeType.none,
  }) : boundingBox = boundingBox ?? _calculateBoundingBox(points);

  static BoundingBox _calculateBoundingBox(List<StrokePoint> points) {
    if (points.isEmpty) return BoundingBox.empty();
    final bbox = BoundingBox.fromPoint(points.first.x, points.first.y);
    for (int i = 1; i < points.length; i++) {
      bbox.expand(points[i].x, points[i].y);
    }
    return bbox;
  }

  /// 새 스트로크 생성 (시작점 포함)
  factory Stroke.create({
    required String id,
    required ToolType toolType,
    required Color color,
    required double width,
    required StrokePoint startPoint,
  }) {
    return Stroke(
      id: id,
      toolType: toolType,
      color: color,
      width: width,
      points: [startPoint],
      boundingBox: BoundingBox.fromPoint(startPoint.x, startPoint.y),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 포인트 추가
  void addPoint(StrokePoint point) {
    points.add(point);
    boundingBox.expand(point.x, point.y);
  }

  /// BoundingBox 재계산
  void recalculateBoundingBox() {
    if (points.isEmpty) {
      boundingBox = BoundingBox.empty();
      return;
    }

    boundingBox = BoundingBox.fromPoint(points.first.x, points.first.y);
    for (int i = 1; i < points.length; i++) {
      boundingBox.expand(points[i].x, points[i].y);
    }
  }

  /// 압력에 따른 실제 굵기 계산
  double getWidthAtPressure(double pressure) {
    // 압력 범위: 0.0 ~ 1.0
    // 굵기 배율: 0.5x ~ 2.0x
    final multiplier = 0.5 + pressure * 1.5;
    return width * multiplier;
  }

  /// 복사본 생성
  Stroke copyWith({
    String? id,
    ToolType? toolType,
    Color? color,
    double? width,
    List<StrokePoint>? points,
    BoundingBox? boundingBox,
    int? timestamp,
    bool? isShape,
    ShapeType? shapeType,
  }) {
    return Stroke(
      id: id ?? this.id,
      toolType: toolType ?? this.toolType,
      color: color ?? this.color,
      width: width ?? this.width,
      points: points ?? List.from(this.points),
      boundingBox: boundingBox ?? this.boundingBox.copy(),
      timestamp: timestamp ?? this.timestamp,
      isShape: isShape ?? this.isShape,
      shapeType: shapeType ?? this.shapeType,
    );
  }

  /// 새 포인트를 추가한 복사본 생성 (불변 패턴)
  Stroke copyWithNewPoint(StrokePoint point) {
    final newPoints = List<StrokePoint>.from(points)..add(point);
    final newBoundingBox = boundingBox.copy()..expand(point.x, point.y);
    return Stroke(
      id: id,
      toolType: toolType,
      color: color,
      width: width,
      points: newPoints,
      boundingBox: newBoundingBox,
      timestamp: timestamp,
      isShape: isShape,
      shapeType: shapeType,
    );
  }

  @override
  String toString() =>
      'Stroke(id: $id, tool: $toolType, points: ${points.length})';
}
